//! What this phone has to run a model with: memory, cores, the chip's name,
//! and room on disk.
//!
//! Only facts, no judgement. Whether a model "runs well", is "tight" or is
//! "too big" is the page's call (`core/models.ts`), so the thresholds can be
//! tuned over the air as phones get measured; this module just has to read
//! the numbers right. Everything comes from places an app may read without a
//! permission: `/proc/meminfo`, the cpufreq tree under `/sys`, Android's
//! system properties through `getprop`, and `statvfs` on the models folder.
//!
//! The parsers take the text rather than the path, so every rule is a unit
//! test with a real phone's file pasted in.

use std::path::Path;

use serde::Serialize;

/// The phone, as the page reads it. Every field that could not be read is
/// `None` rather than a guess.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Device {
    /// All the memory the kernel manages, which is a little under the number on
    /// the box (a 12 GB phone reports about 11.2 GB).
    pub total_ram_bytes: Option<u64>,
    /// What the kernel says could be handed out now without swapping.
    pub available_ram_bytes: Option<u64>,
    pub cores: u32,
    /// Cores above the slowest tier: the ones generation should run on.
    pub fast_cores: Option<u32>,
    /// `ro.soc.model`, such as "SM8850" (Android 12 and later).
    pub chip: Option<String>,
    /// `ro.soc.manufacturer`, such as "QTI".
    pub chip_maker: Option<String>,
    /// `ro.product.model`, such as "SM-F976U".
    pub phone: Option<String>,
    /// `ro.product.marketname` or `ro.product.vendor.marketname` where the
    /// maker sets one ("Galaxy Z Fold8").
    pub phone_name: Option<String>,
    /// Free space where models are kept.
    pub free_disk_bytes: Option<u64>,
}

/// Reads everything this phone will say about itself. `models` is the folder
/// models download into, for the free space.
pub fn read(models: Option<&Path>) -> Device {
    let meminfo = std::fs::read_to_string("/proc/meminfo").unwrap_or_default();
    let (total_ram_bytes, available_ram_bytes) = parse_meminfo(&meminfo);
    let cores = std::thread::available_parallelism().map(|n| n.get() as u32).unwrap_or(0);
    Device {
        total_ram_bytes,
        available_ram_bytes,
        cores,
        fast_cores: fast_cores(&max_frequencies(cores)),
        chip: property("ro.soc.model"),
        chip_maker: property("ro.soc.manufacturer"),
        phone: property("ro.product.model"),
        phone_name: property("ro.product.marketname").or_else(|| property("ro.product.vendor.marketname")),
        free_disk_bytes: models.and_then(free_bytes),
    }
}

/// `MemTotal` and `MemAvailable`, in bytes. The file counts in kB (really KiB).
pub fn parse_meminfo(text: &str) -> (Option<u64>, Option<u64>) {
    let field = |name: &str| {
        text.lines().find_map(|line| {
            let rest = line.strip_prefix(name)?.strip_prefix(':')?;
            let kib: u64 = rest.trim().trim_end_matches("kB").trim().parse().ok()?;
            Some(kib * 1024)
        })
    };
    (field("MemTotal"), field("MemAvailable"))
}

/// Each core's top frequency in kHz, in core order; a core whose file cannot be
/// read is left out.
fn max_frequencies(cores: u32) -> Vec<u64> {
    (0..cores)
        .filter_map(|n| std::fs::read_to_string(format!("/sys/devices/system/cpu/cpu{n}/cpufreq/cpuinfo_max_freq")).ok())
        .filter_map(|text| text.trim().parse().ok())
        .collect()
}

/// How many cores are faster than the slowest tier. A phone's chip mixes tiers
/// (the Snapdragon 8 Elite has two performance cores and six efficiency cores
/// at a lower top speed); llama.cpp decodes about as fast as its slowest
/// thread, so the page sizes threads to this. `None` when the tiers could not
/// be read, and all of them when every core is alike.
pub fn fast_cores(frequencies: &[u64]) -> Option<u32> {
    let slowest = *frequencies.iter().min()?;
    let fast = frequencies.iter().filter(|&&f| f > slowest).count() as u32;
    Some(if fast == 0 { frequencies.len() as u32 } else { fast })
}

/// One Android system property, or `None` off Android, when it is unset, or
/// when `getprop` is not there.
fn property(name: &str) -> Option<String> {
    if !cfg!(target_os = "android") {
        return None;
    }
    let output = std::process::Command::new("getprop").arg(name).output().ok()?;
    clean_property(&String::from_utf8_lossy(&output.stdout))
}

/// `getprop` prints an unset property as an empty line.
pub fn clean_property(raw: &str) -> Option<String> {
    let value = raw.trim();
    (!value.is_empty()).then(|| value.to_string())
}

#[cfg(unix)]
fn free_bytes(path: &Path) -> Option<u64> {
    use std::ffi::CString;
    use std::os::unix::ffi::OsStrExt;
    let c_path = CString::new(path.as_os_str().as_bytes()).ok()?;
    let mut stat: libc::statvfs = unsafe { std::mem::zeroed() };
    // SAFETY: `c_path` is a valid NUL-terminated string and `stat` is a
    // properly sized, writable statvfs for the call to fill.
    let rc = unsafe { libc::statvfs(c_path.as_ptr(), &mut stat) };
    (rc == 0).then(|| stat.f_bavail as u64 * stat.f_frsize as u64)
}

#[cfg(not(unix))]
fn free_bytes(_path: &Path) -> Option<u64> {
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_memory_from_a_real_meminfo() {
        let text = "MemTotal:       11530924 kB\nMemFree:          412312 kB\nMemAvailable:    5230120 kB\nBuffers:            2048 kB\n";
        let (total, available) = parse_meminfo(text);
        assert_eq!(total, Some(11_530_924 * 1024));
        assert_eq!(available, Some(5_230_120 * 1024));
        assert_eq!(parse_meminfo("nothing here"), (None, None));
    }

    #[test]
    fn counts_the_cores_above_the_slowest_tier() {
        // A 2 + 6 layout: two performance cores at 4.32 GHz, six at 3.53 GHz.
        let elite = [3_532_800, 3_532_800, 3_532_800, 3_532_800, 3_532_800, 3_532_800, 4_320_000, 4_320_000];
        assert_eq!(fast_cores(&elite), Some(2));
        // A 1 + 3 + 4 layout: the four little cores are the slowest tier.
        let tiers = [2_000_000, 2_000_000, 2_000_000, 2_000_000, 3_200_000, 3_200_000, 3_200_000, 3_800_000];
        assert_eq!(fast_cores(&tiers), Some(4));
        assert_eq!(fast_cores(&[2_400_000; 4]), Some(4), "all alike: all of them");
        assert_eq!(fast_cores(&[]), None);
    }

    #[test]
    fn an_unset_property_is_none() {
        assert_eq!(clean_property("\n"), None);
        assert_eq!(clean_property("SM8850\n"), Some("SM8850".to_string()));
    }

    #[test]
    fn reads_this_machine_without_panicking() {
        let here = read(Some(Path::new(".")));
        assert!(here.cores > 0);
    }
}
