//! The Mac's sound, through a Core Audio process tap (macOS 14.2 and later).
//!
//! A tap is Apple's door to what other apps are playing, without a virtual
//! audio driver to install: a `CATapDescription` says which processes (here,
//! every one but this app, so a sound Ghost.md makes is never recorded back
//! into its own tape), `AudioHardwareCreateProcessTap` makes it, and an
//! aggregate device with the tap in its tap list is what an IOProc reads it
//! from. The tap is mono (`initMonoGlobalTapButExcludeProcesses`), since the
//! tape is, and unmuted, so the person still hears the call. The aggregate is
//! private (no other app sees it in its device list) and is clocked by the
//! default output device, as Apple's own sample and AudioCap set it up.
//!
//! WHY THE TAP'S TWO FUNCTIONS ARE LOOKED UP, NOT LINKED. The app still runs on
//! macOS 13.1 (tauri.conf.json `minimumSystemVersion`; Matt: older Macs keep
//! mic-only meetings), and a Mach-O that links a symbol its OS does not have
//! does not launch at all: dyld stops before `main` over the one missing name.
//! Rust has no `weak_import`, so `AudioHardwareCreateProcessTap` and
//! `AudioHardwareDestroyProcessTap` are found with `dlsym` at the moment they are
//! wanted, and a Mac without them answers "not here" (`unsupported`). Everything
//! else used below is from macOS 10.x. `CATapDescription` is an Objective-C
//! class, which objc2 looks up by name when it is first used, so it costs an old
//! Mac nothing as long as nothing asks for it there, and `unsupported` is asked
//! first.
//!
//! THE CONSENT. The first start on a Mac raises "System Audio Recording Only"
//! with NSAudioCaptureUsageDescription's sentence (Info.macos.plist). A refusal
//! is not an error anywhere in this API: the tap delivers zeros. So the page is
//! told what was heard (`Mixer::heard`), and says where the switch is when
//! nothing has been.

use std::ffi::{c_void, CStr};
use std::mem::{size_of, MaybeUninit};
use std::ptr::NonNull;
use std::sync::{Arc, OnceLock};

use objc2::rc::Retained;
use objc2::runtime::AnyObject;
use objc2::{AnyThread, Message};
use objc2_core_audio::{
    kAudioAggregateDeviceIsPrivateKey, kAudioAggregateDeviceIsStackedKey, kAudioAggregateDeviceMainSubDeviceKey,
    kAudioAggregateDeviceNameKey, kAudioAggregateDeviceSubDeviceListKey, kAudioAggregateDeviceTapAutoStartKey,
    kAudioAggregateDeviceTapListKey, kAudioAggregateDeviceUIDKey, kAudioDevicePropertyDeviceUID,
    kAudioDevicePropertyNominalSampleRate, kAudioHardwarePropertyDefaultOutputDevice,
    kAudioHardwarePropertyTranslatePIDToProcessObject, kAudioObjectPropertyElementMain, kAudioObjectPropertyScopeGlobal,
    kAudioObjectSystemObject, kAudioObjectUnknown, kAudioSubDeviceUIDKey, kAudioSubTapDriftCompensationKey,
    kAudioSubTapUIDKey, kAudioTapPropertyFormat, AudioDeviceCreateIOProcID, AudioDeviceDestroyIOProcID,
    AudioDeviceIOProcID, AudioDeviceStart, AudioDeviceStop, AudioHardwareCreateAggregateDevice,
    AudioHardwareDestroyAggregateDevice, AudioObjectGetPropertyData, AudioObjectID, AudioObjectPropertyAddress,
    CATapDescription,
};
use objc2_core_audio_types::{
    kAudioFormatFlagIsFloat, kAudioFormatLinearPCM, AudioBuffer, AudioBufferList, AudioStreamBasicDescription,
    AudioTimeStamp,
};
use objc2_core_foundation::CFDictionary;
use objc2_foundation::{NSArray, NSCopying, NSDictionary, NSNumber, NSOperatingSystemVersion, NSProcessInfo, NSString, NSUUID};

use super::Mixer;

/// Said on a Mac older than the taps.
const TOO_OLD: &str = "Recording the computer's sound needs macOS 14.2 or later. On this Mac a meeting records the microphone.";

type CreateTap = unsafe extern "C" fn(*const AnyObject, *mut AudioObjectID) -> i32;
type DestroyTap = unsafe extern "C" fn(AudioObjectID) -> i32;

/// The tap's two functions, found once (see the header).
fn tap_functions() -> Option<(CreateTap, DestroyTap)> {
    static FOUND: OnceLock<Option<(CreateTap, DestroyTap)>> = OnceLock::new();
    *FOUND.get_or_init(|| {
        let create = find(c"AudioHardwareCreateProcessTap")?;
        let destroy = find(c"AudioHardwareDestroyProcessTap")?;
        // SAFETY: both are the C functions of these names in CoreAudio.framework
        // (AudioHardware.h, macOS 14.2), whose signatures the types above copy.
        Some(unsafe { (std::mem::transmute::<*mut c_void, CreateTap>(create), std::mem::transmute::<*mut c_void, DestroyTap>(destroy)) })
    })
}

fn find(name: &CStr) -> Option<*mut c_void> {
    // SAFETY: a lookup by name in the images already loaded; CoreAudio is,
    // because this crate links its older functions.
    let found = unsafe { libc::dlsym(libc::RTLD_DEFAULT, name.as_ptr()) };
    (!found.is_null()).then_some(found)
}

/// Why this Mac cannot tap its sound, or None when it can.
pub fn unsupported() -> Option<&'static str> {
    let at_least = NSProcessInfo::processInfo().isOperatingSystemAtLeastVersion(NSOperatingSystemVersion {
        majorVersion: 14,
        minorVersion: 2,
        patchVersion: 0,
    });
    if !at_least || tap_functions().is_none() {
        return Some(TOO_OLD);
    }
    None
}

/// One property of a Core Audio object, read as `T`, with an optional qualifier.
///
/// # Safety
/// `T` must be the type Core Audio writes for `selector` (AudioHardware.h).
unsafe fn property<T: Copy>(object: AudioObjectID, selector: u32, qualifier: Option<&[u8]>) -> Result<T, i32> {
    let address = AudioObjectPropertyAddress {
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain,
    };
    let mut size = size_of::<T>() as u32;
    let mut value = MaybeUninit::<T>::zeroed();
    let (qualifier_size, qualifier_data) = match qualifier {
        Some(bytes) => (bytes.len() as u32, bytes.as_ptr().cast::<c_void>()),
        None => (0, std::ptr::null()),
    };
    let status = AudioObjectGetPropertyData(
        object,
        NonNull::from(&address),
        qualifier_size,
        qualifier_data,
        NonNull::from(&mut size),
        NonNull::new_unchecked(value.as_mut_ptr().cast()),
    );
    if status != 0 {
        return Err(status);
    }
    Ok(value.assume_init())
}

fn key(name: &CStr) -> Retained<NSString> {
    NSString::from_str(name.to_str().unwrap_or_default())
}

fn object<T: Message>(value: Retained<T>) -> Retained<AnyObject> {
    // SAFETY: every Objective-C object is an AnyObject.
    unsafe { Retained::cast_unchecked(value) }
}

fn dictionary(pairs: Vec<(&CStr, Retained<AnyObject>)>) -> Retained<NSDictionary<NSString, AnyObject>> {
    let keys: Vec<Retained<NSString>> = pairs.iter().map(|(name, _)| key(name)).collect();
    let key_refs: Vec<&NSString> = keys.iter().map(|k| &**k).collect();
    let values: Vec<Retained<AnyObject>> = pairs.into_iter().map(|(_, value)| value).collect();
    NSDictionary::from_retained_objects(&key_refs, &values)
}

fn failed(what: &str, status: i32) -> String {
    format!("The computer's sound could not be opened: {what} failed (Core Audio {status}). The meeting records the microphone.")
}

/// An open tap: the tap, the aggregate device it is read through, the IOProc
/// on it, and the mixer that IOProc writes into. Dropping it closes them all,
/// in the order that guarantees the IOProc has returned before the mixer it
/// points at can go.
pub struct Tap {
    tap: AudioObjectID,
    aggregate: AudioObjectID,
    proc_id: AudioDeviceIOProcID,
    started: bool,
    /// `Arc::into_raw` of the mixer, the IOProc's client data.
    mixer: *const Mixer,
}

// SAFETY: object ids are plain integers Core Audio accepts from any thread, and
// `mixer` is an Arc's pointer, released once, in `drop`, after the IOProc that
// reads it has been stopped.
unsafe impl Send for Tap {}

impl Tap {
    /// Everything opened, the frames flowing into `mixer`, or why not. Blocks
    /// on coreaudiod, and on the consent the first time a Mac is asked.
    pub fn open(mixer: Arc<Mixer>) -> Result<Tap, String> {
        let (create, _) = tap_functions().ok_or_else(|| TOO_OLD.to_string())?;
        let mut opened = Tap {
            tap: kAudioObjectUnknown,
            aggregate: kAudioObjectUnknown,
            proc_id: None,
            started: false,
            mixer: std::ptr::null(),
        };

        // This app's own process object, left out of the tap. None when it has
        // never played a sound, in which case there is nothing of it to hear.
        // The WebView plays through WebKit's own GPU process, not this one; the
        // recorder's only sound there is its silent sink (capture/audio.ts).
        let pid = std::process::id() as i32;
        // SAFETY: the qualifier is a pid_t and the answer an AudioObjectID (AudioHardware.h).
        let own = unsafe {
            property::<AudioObjectID>(kAudioObjectSystemObject as AudioObjectID, kAudioHardwarePropertyTranslatePIDToProcessObject, Some(&pid.to_ne_bytes()))
        }
        .ok()
        .filter(|id| *id != kAudioObjectUnknown);
        let exclude: Vec<Retained<NSNumber>> = own.into_iter().map(NSNumber::new_u32).collect();
        let exclude = NSArray::from_retained_slice(&exclude);

        // SAFETY: `unsupported` (checked by the caller, and `tap_functions` above)
        // says this macOS has the class. The description is retained for the call.
        let description = unsafe { CATapDescription::initMonoGlobalTapButExcludeProcesses(CATapDescription::alloc(), &exclude) };
        // SAFETY: plain property setters on a description nothing else holds.
        let tap_uid = unsafe {
            description.setName(&NSString::from_str("Ghost.md meeting"));
            description.setPrivate(true);
            description.UUID().UUIDString()
        };
        // SAFETY: a live CATapDescription and a place for the id, as the function takes.
        let status = unsafe { create(Retained::as_ptr(&description).cast(), &mut opened.tap) };
        if status != 0 || opened.tap == kAudioObjectUnknown {
            return Err(failed("the tap", status));
        }

        // SAFETY: kAudioTapPropertyFormat answers an AudioStreamBasicDescription.
        let format = unsafe { property::<AudioStreamBasicDescription>(opened.tap, kAudioTapPropertyFormat, None) }
            .map_err(|status| failed("reading the tap's format", status))?;
        if format.mFormatID != kAudioFormatLinearPCM || format.mFormatFlags & kAudioFormatFlagIsFloat == 0 || format.mBitsPerChannel != 32 {
            return Err("The computer's sound came in a format Ghost.md does not read. The meeting records the microphone.".to_string());
        }

        // The default output device's UID, the aggregate's clock.
        // SAFETY: the default output device is an AudioObjectID; a device's UID is a CFStringRef the caller owns.
        let output = unsafe { property::<AudioObjectID>(kAudioObjectSystemObject as AudioObjectID, kAudioHardwarePropertyDefaultOutputDevice, None) }
            .map_err(|status| failed("finding the output device", status))?;
        let output_uid = unsafe { property::<*mut NSString>(output, kAudioDevicePropertyDeviceUID, None) }
            .ok()
            // SAFETY: a +1 CFString, toll-free bridged to NSString; Retained releases it.
            .and_then(|raw| unsafe { Retained::from_raw(raw) })
            .ok_or_else(|| failed("reading the output device", -1))?;

        let yes = || object(NSNumber::new_bool(true));
        let no = || object(NSNumber::new_bool(false));
        let sub_device = dictionary(vec![(kAudioSubDeviceUIDKey, object(output_uid.copy()))]);
        let sub_tap = dictionary(vec![(kAudioSubTapUIDKey, object(tap_uid)), (kAudioSubTapDriftCompensationKey, yes())]);
        let description = dictionary(vec![
            (kAudioAggregateDeviceNameKey, object(NSString::from_str("Ghost.md meeting"))),
            (kAudioAggregateDeviceUIDKey, object(NSUUID::new().UUIDString())),
            (kAudioAggregateDeviceMainSubDeviceKey, object(output_uid)),
            (kAudioAggregateDeviceIsPrivateKey, yes()),
            (kAudioAggregateDeviceIsStackedKey, no()),
            (kAudioAggregateDeviceTapAutoStartKey, yes()),
            (kAudioAggregateDeviceSubDeviceListKey, object(NSArray::from_retained_slice(&[sub_device]))),
            (kAudioAggregateDeviceTapListKey, object(NSArray::from_retained_slice(&[sub_tap]))),
        ]);
        // SAFETY: an NSDictionary is a CFDictionary (toll-free bridged), alive for the call.
        let status = unsafe {
            let cf = &*(Retained::as_ptr(&description) as *const CFDictionary);
            AudioHardwareCreateAggregateDevice(cf, NonNull::from(&mut opened.aggregate))
        };
        if status != 0 || opened.aggregate == kAudioObjectUnknown {
            return Err(failed("the aggregate device", status));
        }

        // The rate the IOProc's frames come at: the aggregate's, which is its
        // clock's; the tap's own if the aggregate will not say.
        // SAFETY: the nominal rate is a Float64.
        let rate = unsafe { property::<f64>(opened.aggregate, kAudioDevicePropertyNominalSampleRate, None) }
            .ok()
            .filter(|rate| *rate > 0.0)
            .unwrap_or(format.mSampleRate);
        mixer.begin(rate);

        opened.mixer = Arc::into_raw(mixer);
        // SAFETY: `io_proc` matches AudioDeviceIOProc, and its client data is
        // the mixer, kept alive until `drop` has stopped and destroyed it.
        let status = unsafe {
            AudioDeviceCreateIOProcID(opened.aggregate, Some(io_proc), opened.mixer as *mut c_void, NonNull::from(&mut opened.proc_id))
        };
        if status != 0 || opened.proc_id.is_none() {
            return Err(failed("the reader", status));
        }
        // SAFETY: a device and an IOProc this function made.
        let status = unsafe { AudioDeviceStart(opened.aggregate, opened.proc_id) };
        if status != 0 {
            return Err(failed("starting", status));
        }
        opened.started = true;
        Ok(opened)
    }
}

impl Drop for Tap {
    fn drop(&mut self) {
        // SAFETY: each id is one `open` made, or unknown and skipped. AudioDeviceStop,
        // called off the IO thread, returns once the IOProc is no longer running.
        unsafe {
            if self.aggregate != kAudioObjectUnknown {
                if self.started {
                    AudioDeviceStop(self.aggregate, self.proc_id);
                }
                if self.proc_id.is_some() {
                    AudioDeviceDestroyIOProcID(self.aggregate, self.proc_id);
                }
                AudioHardwareDestroyAggregateDevice(self.aggregate);
            }
            if self.tap != kAudioObjectUnknown {
                if let Some((_, destroy)) = tap_functions() {
                    destroy(self.tap);
                }
            }
            if !self.mixer.is_null() {
                let mixer = Arc::from_raw(self.mixer);
                mixer.end();
            }
        }
    }
}

/// Core Audio's real-time thread, every IO cycle: the tap's frames into the
/// mixer. The tap is the aggregate's last input stream (its sub device, the
/// output device, comes first and usually has no inputs at all), so the last
/// buffer is the one read.
unsafe extern "C-unwind" fn io_proc(
    _device: AudioObjectID,
    _now: NonNull<AudioTimeStamp>,
    input: NonNull<AudioBufferList>,
    _input_time: NonNull<AudioTimeStamp>,
    _output: NonNull<AudioBufferList>,
    _output_time: NonNull<AudioTimeStamp>,
    client: *mut c_void,
) -> i32 {
    if client.is_null() {
        return 0;
    }
    let mixer = &*(client as *const Mixer);
    let list = input.as_ptr();
    let count = (*list).mNumberBuffers as usize;
    if count == 0 {
        return 0;
    }
    // mBuffers is declared [AudioBuffer; 1] and runs on for mNumberBuffers, so
    // the last is reached from the list's own pointer, not through a reference
    // to a one-element array.
    let first = std::ptr::addr_of!((*list).mBuffers).cast::<AudioBuffer>();
    let last = &*first.add(count - 1);
    if last.mData.is_null() || last.mDataByteSize == 0 {
        return 0;
    }
    let samples = std::slice::from_raw_parts(last.mData as *const f32, last.mDataByteSize as usize / size_of::<f32>());
    mixer.hear(samples, last.mNumberChannels as usize);
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    /// By hand, on a Mac on 14.2 or later with something playing: `cargo test
    /// --lib system_audio -- --ignored --nocapture`. Ignored because the first
    /// run raises the consent for whatever runs the test (Terminal, say), which
    /// no test should do on its own; refused, it opens and hears nothing.
    #[test]
    #[ignore]
    fn a_tap_opens_hears_and_closes_on_this_mac() {
        if let Some(reason) = unsupported() {
            eprintln!("skipped: {reason}");
            return;
        }
        let mixer = Arc::new(Mixer::default());
        let tap = Tap::open(Arc::clone(&mixer)).expect("the tap opens");
        std::thread::sleep(std::time::Duration::from_secs(3));
        let mut chunk = vec![0.0f32; 3_200];
        mixer.mix_into(&mut chunk);
        eprintln!("heard: {}, first samples: {:?}", mixer.heard(), &chunk[..8]);
        drop(tap);
        assert!(!mixer.running(), "closing the tap ends the mix");
    }
}
