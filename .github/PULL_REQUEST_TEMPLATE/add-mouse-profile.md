## Mouse profile

- Exact model:
- Connection tested (wired, receiver, or Bluetooth):
- Profile descriptor:

## Summary

<!-- Describe the physical layout and the profile/catalog behavior this adds or corrects. -->

## Evidence

<!-- Explain how record numbers, product IDs, and capabilities were determined. Include source links. -->

- Sources:
- Hardware used:
- Read/inspect result:
- Save and full read-back result, if write support is enabled:

## Safety and validation checklist

- [ ] This descriptor is for one exact mouse model, not a combined family.
- [ ] `id`, `name`, device-name matches, and product IDs are exact and unique.
- [ ] Button record numbers were verified against the device/profile data.
- [ ] Scroll-wheel and hidden non-programmable records are mapped where applicable.
- [ ] `profileIO.supported` remains false/read-only unless the complete write and read-back path was tested on real hardware.
- [ ] Uncertainty is documented in `profileIO.notes`.
- [ ] Relevant tests and documentation are added or updated.
- [ ] I did not include device backups, credentials, or other local-only files.

## Checks

- [ ] `make lint`
- [ ] `make test-modified` (or explain why it is not applicable)
