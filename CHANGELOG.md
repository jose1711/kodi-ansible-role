# Changelog for `jose1711.kodi_ansible_role`

This file lists all notable changes to this project.

## Unreleased

### Added

- Support for Alpine Linux (#8).
- Project contribution guide (#8).
- Support `system` boolean and `gid` numeric attributes in `kodi_groups`
  entries, permitting greater end-user control over group creation logic (#8).
- Add the new `kodi_service` variable for managing the Kodi service,
  emphasizing that this role supports both system and non-systemd service
  managers (#8).

### Changed

- Create (if necessary) all groups in `kodi_groups` (#8).
- Use the `service` module rather than the `systemd` for managing the Kodi
  service, thus supporting (e.g.) OpenRC on Alpine Linux (#8).
- Deprecate (but do not yet remove or ignore) the `kodi_systemd_service`
  variable in favor of using the newly-introduced `kodi_service` variable (#8).
- Exclude testing- and development-only files from the role archive distributed
  via Ansible Galaxy (#8).

### Fixed

- Use `root` as `kodi_user` on LibreELEC (#8).
- Use the `wait_for` module instead of the `pause` module; now it should be
  possible to apply this role under the `free` strategy (#8).
- Gracefully handle the absence of one or more prerequisites of the Ansible
  `group` module (e.g. the absence of the `groupadd` command on LibreELEC)
  (#10).
- Unpack "complex" group specifications (dictionaries) when constructing the
  `groups` attribute of the Ansible `user` task that creates `kodi_user`; this
  task expects a list of strings specifying group names (#10).
- Omit `psmisc` from `vagrant-libvirt-create-box`'s dependency list when
  running on Darwin, where `psmisc` is not available (#11).
