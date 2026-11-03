# Third-party notices

The HID mouse report descriptor in `Sources/CursorCore/Pointer.swift` is adapted
from [xhoantran/iphone-use](https://github.com/xhoantran/iphone-use),
`Sources/iPhoneUse/HIDReportMap.swift`, blob
`1fb6a4996930e9a42d57a323bc2a03bc5da747e7` (reviewed November 3, 2026).
The absolute-position plus relative-button strategy also follows that project's research.

## iPhone Use — MIT License

Copyright (c) 2026 NewWave AI

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## iPhone Use relative drag research — MIT License

The measured acceleration table in `Sources/CursorCore/RelativeDrag.swift` is
adapted from [YueChen-C/iPhone-use](https://github.com/YueChen-C/iPhone-use),
`Sources/iPhoneUse/Input/DeviceInput.swift`, blob
`81b7118ece9cd98f001edd6a9b5d38fcc9abaeb6` (reviewed November 3, 2026).
Its observation that held-touch movement must use the relative collection also
informed the drag correction. The table is an estimate, not iPhone 16 calibration.

Copyright (c) 2026 YueChen

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Other technical references

- [sryo/clak CoreBluetooth HID notes](https://github.com/sryo/clak/blob/main/docs/corebluetooth-hid-notes.md): full-form service UUIDs, encrypted GATT attributes and report references. Referenced for interoperability; no source files copied.
- [jqssun/darwin-bt-remote](https://github.com/jqssun/darwin-bt-remote): evaluated as an alternative. No AGPL source incorporated.

The Cursor has no third-party Swift package dependencies.
