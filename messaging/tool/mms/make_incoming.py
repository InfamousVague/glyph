#!/usr/bin/env python3
"""
Makes an incoming picture message for an emulator out of one the app sent (tool/mms/README.md).

    python3 tool/mms/make_incoming.py /tmp/mms/post-1.bin /tmp/mms m1

Writes /tmp/mms/serve/m1, the message as a carrier hands it over (m-retrieve-conf, from +15559870000, with the
picture and layout of the message given), and /tmp/mms/m1.push.pdu, the SMS that announces it: push that to the
emulator and hand it over with Inject.
"""
import os
import struct
import sys
import time

post, out, name = sys.argv[1], sys.argv[2], sys.argv[3]
sent = open(post, 'rb').read()
at = max(sent.find(b'\x90\x80\x84'), sent.find(b'\x90\x81\x84'))
assert at > 0, 'this is not a message the app sent: no Content-Type after its read-report header'
body = sent[at + 2:]                      # from the Content-Type header on: the layout and the picture
sender = b'+15559870000/TYPE=PLMN'
me = b'+15551234567/TYPE=PLMN'            # the emulator's own number
conf = (b'\x8c\x84' + b'\x98r-' + name.encode() + b'\x00' + b'\x8d\x92' + b'\x8b' + name.encode() + b'@fake\x00'
        + b'\x85\x04' + struct.pack('>I', int(time.time()))
        + b'\x89' + bytes([len(sender) + 2]) + b'\x80' + sender + b'\x00' + b'\x97' + me + b'\x00' + body)
os.makedirs(os.path.join(out, 'serve'), exist_ok=True)
open(os.path.join(out, 'serve', name), 'wb').write(conf)

location = b'http://10.0.2.2:18765/get/' + name.encode()
ind = (b'\x8c\x82' + b'\x98n-' + name.encode() + b'\x00' + b'\x8d\x92'
       + b'\x89' + bytes([len(sender) + 2]) + b'\x80' + sender + b'\x00' + b'\x8a\x80'
       + b'\x8e\x03' + struct.pack('>I', len(conf))[1:] + b'\x88\x05\x81\x03\x02\xa3\x00' + b'\x83' + location + b'\x00')
wsp = b'\x00\x06\x03\xbe\xaf\x84' + ind   # a WAP push of application/vnd.wap.mms-message to the MMS client
data = b'\x06\x05\x04\x0b\x84\x23\xf0' + wsp
assert len(data) <= 140, 'too long for one SMS: shorten the name'
digits = '15559870000'
swapped = ''.join(digits[k + 1] + digits[k] if k + 1 < len(digits) else 'F' + digits[k] for k in range(0, len(digits), 2))
# SMS-DELIVER with a header, from the sender, 8-bit data of class 1 (the only class the phone lets be handed to it)
sms = bytes([0x00, 0x44, len(digits), 0x91]) + bytes.fromhex(swapped) + b'\x00\x15' + bytes.fromhex('62113191530000') + bytes([len(data)]) + data
open(os.path.join(out, name + '.push.pdu'), 'wb').write(sms)
print('%s: message %d bytes in serve/, announcement %d bytes' % (name, len(conf), len(sms)))
