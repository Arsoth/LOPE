# Third-party notices

The implementation references listed in [docs/PROTOCOL.md](docs/PROTOCOL.md)
were used as research material. This repository does not include copied source
files from those projects; its HID++ implementation was written independently.
The notices below document the upstream licenses so the licensing boundary is
clear if the implementation is extended later.

## Project license

Project source is licensed under **GPL-2.0-or-later**. This is intentional:
the “or later” option permits a combined work to be distributed under GPLv3 if
GPLv3-only code is ever incorporated. It does not permit distributing a GPLv3
component under GPLv2-only terms.

## Referenced projects

| Project | Referenced material | Upstream license | Compliance note |
| --- | --- | --- | --- |
| [Solaar](https://github.com/pwr-Solaar/Solaar) | [HID++ 2.0 feature implementation](https://github.com/pwr-Solaar/Solaar/blob/master/lib/logitech_receiver/hidpp20.py) | GPL-2.0-or-later | Compatible with this project’s license. |
| [libratbag](https://github.com/libratbag/libratbag) | [HID++ 2.0 header](https://github.com/libratbag/libratbag/blob/master/src/hidpp20.h) | MIT | Permissive; no libratbag source is included here. |
| [lowtech](https://github.com/orthory/lowtech) | [HID++ transport](https://github.com/orthory/lowtech/blob/main/src/hidpp.rs), [onboard implementation](https://github.com/orthory/lowtech/blob/main/src/onboard.rs) | GPL-2.0-or-later | Compatible with this project’s license. |
| [omm.py](https://github.com/lexr1/omm.py) | Reference implementation | GPL-3.0 (GitHub-detected) | No omm.py source is included here. If code is incorporated, distribute the combined work under GPLv3 or a compatible later choice—not GPLv2-only. |

If source code from an upstream project is added in the future, retain its
copyright and license notices, identify the affected files, and update this
document with the applicable license text or a bundled copy as required by
that license.
