[`tests/test.yml`]: /tests/test.yml
[`.github/workflows/ci.yml`]: /.github/workflows/ci.yml
[Nix development shell]: #nix-development-shell

# Contributing to `jose1711.kodi_ansible_role`

## Nix development shell

This project includes a development environment using the [Nix package
manager](https://nixos.org).  The environment provides tools for working with
the `jose1711.kodi-ansible-role` codebase, including Ansible itself, plus
[Vagrant](#vagrant-environment) and helpers for executing [GitHub Actions
jobs](#github-actions-suite).

Please see [here](https://nixos.org/download#download-nix) for instructions on
installing the Nix package manager, and see
[here](https://nix.dev/tutorials/first-steps/) for a getting-started-with-Nix
tutorial.

Once you have installed the Nix package manager, you can enter the
Nix development shell by running the following command from inside this
project's working tree:

```console
$ nix --extra-experimental-features 'flakes nix-command' develop
```

This will start a new shell with development tooling available (print the value
of the `PATH` environment variable inside the shell for some of the gory
details).

When you are done with your development environment, you can exit the shell as
usual (press `<ctrl-d>`, or run `exit`).

## Vagrant environment

This project includes a Vagrant environment for testing the
`jose1711.kodi_ansible_role` Ansible role on several Linux distributions.  As
of this writing, those distributions are:

1. Alpine Linux 3.19
2. Arch Linux
3. Debian 11 (bullseye)
4. Debian 12 (bookworm)
5. Ubuntu 22.04 LTS (Jammy Jellyfish)
6. Ubuntu 23.04 LTS (Lunar Lobster)
7. LibreELEC 11.0.6
8. OSMC 20240205

This Vagrant environment supports the
[`libvirt` provider](https://vagrant-libvirt.github.io/vagrant-libvirt/)[^provider-support].

[^provider-support]: Some of the Vagrant boxes employed in this environment may
                     support other providers, but the LibreELEC and OSMC boxes
                     support **only** `libvirt`.

To use this Vagrant environment, you will need to install Vagrant itself, as
well as the `vagrant-libvirt` provider plugin[^vagrant-in-nix-devshell].  Please
see the [`vagrant-libvirt` installation instructions](https://vagrant-libvirt.github.io/vagrant-libvirt/installation.html)
for guidance on installing and using the provider plugin.

[^vagrant-in-nix-devshell]: The [Nix development shell][] provides the
                            `vagrant` executable and the `vagrant-libvirt`
                            provider plugin.

Vagrant provisions its machines using the [`tests/test.yml`][] playbook, which
installs the prerequisites for running Ansible against those machines and then
applies this Ansible role.

> [!IMPORTANT]
> If you add support for a new distribution to this Ansible role, please try to
> add a Vagrant guest that runs this distribution, and, if necessary, update
> [`tests/test.yml`][] to install Ansible's dependencies on this guest.
> Additionally, please add a description of the distribution to the list above.

### Just-in-time Vagrant box builds

The LibreELEC and OSMC machines use custom Vagrant boxes built with scripts
that live in this project
([`create-libreelec-box`](/scripts/create-libreelec-box) and
[`create-osmc-box`](/scripts/create-osmc-box), respectively).  The Vagrant
environment is configured to build these boxes on-demand; effectively, the
boxes are built upon `vagrant up` if they are not already installed.  This
means that, in order to run these machines, you'll need to ensure that all
box-building prerequisites are available on your Vagrant host
system[^box-building-in-nix-devshell].

[^box-building-in-nix-devshell]: The [Nix development shell][] provides all of
                                 these prerequisites.

#### Using OSMC under Vagrant

The OSMC box requires some special handling:

1. OSMC publishes images for a small number of platforms and architectures
   ([Raspberry Pi, Vero, and Apple TV](https://osmc.tv/download/)); there are
   no prebuilt `x86_64` images (as there are [for LibreELEC](https://archive.libreelec.tv/archive/)).
2. The kernel included in OSMC images does not support certain modules required
   for proper operation under [QEMU's `virt` Generic Virtual Platform](https://www.qemu.org/docs/master/system/riscv/virt.html).

To avoid having to run the OSMC guest under [QEMU's Raspberry Pi board emulation](https://www.qemu.org/docs/master/system/arm/raspi.html),
which is effective but very slow, we instead build a custom kernel and initial
RAM disk for the `aarch64` architecture and run the guest using the `virt`
platform.  This makes the OSMC guest run faster, but comes with some downsides:

1. The kernel and initial RAM disk are built with [the NixOS module
   system](https://nix.dev/tutorials/module-system/module-system.html), and
   building the OSMC Vagrant box therefore requires installing and running the
   Nix package manager.
2. If the `libvirt` daemon runs as an unprivileged user, it may not be able to
   load the kernel and initial RAM disk from the location under
   [`VAGRANT_HOME`](https://developer.hashicorp.com/vagrant/docs/other/environmental-variables#vagrant_home)
   where Vagrant extracted the `.box` file, so the OSMC box includes a
   `Vagrantfile` that, among other things, copies the kernel and initial RAM
   disk to a world-readable location before Vagrant boots the OSMC guest (and
   attempts to clean up these files before Vagrant exits).

> [!WARNING]
> There is a bug in Vagrant that may cause problems on the first boot of the
> OSMC machine.  If the first `vagrant up` (or `vagrant up osmc`) hangs or
> crashes, please try re-running the command.

### Cleaning up deprecated or renamed Vagrant machine

From time to time, the names of Vagrant machines defined in the Vagrantfile may
change (for instance, the machine formerly known as `ubuntu` may be renamed to
`ubuntu2204`), or machines may be removed.  If the Vagrantfile changes in a
backward-incompatible way, you may need to run `vagrant global-status` to
retrieve the unique IDs associated with machines that have been renamed in or
removed from the Vagrantfile, then use those IDs to destroy the machines:

```shell-session
$ vagrant destroy -f ubuntu
The machine with the name 'ubuntu' was not found configured for
this Vagrant environment.

$ vagrant global-status
id       name   provider state   directory
------------------------------------------------------------------------------
a2cfdaf  ubuntu libvirt running /path/to/kodi-ansible-role

The above shows information about all known Vagrant environments
on this machine. This data is cached and may not be completely
up-to-date (use "vagrant global-status --prune" to prune invalid
entries). To interact with any of the machines, you can go to that
directory and run Vagrant, or you can use the ID directly with
Vagrant commands from any directory. For example:
"vagrant destroy 1a2b3c4d"

$ vagrant destroy -f a2cfdaf
==> ubuntu: Removing domain...
==> ubuntu: Deleting the machine folder
```

## GitHub Actions suite

This project uses [GitHub Actions](https://docs.github.com/en/actions) for
automated testing.  The main workflow definition is
[`.github/workflows/ci.yml`][].  As of this writing, the workflow applies this
Ansible role to containers based upon the following images:

1. `alpine:3`
2. `archlinux/archlinux`
3. `debian:11`
4. `debian:12`
5. `ubuntu:22.04`
6. `ubuntu:23.04`

Please ensure that the workflow succeeds when run against your branch.

You can run the GitHub Actions workflow locally using
[`act`](https://github.com/nektos/act):[^act-in-nix-devshell]

[^act-in-nix-devshell]: The [Nix development shell][] provides the `act`
                        executable.

```console
$ act -j native
```

This will run the `native` job from [`.github/workflows/ci.yml`][].

> [!IMPORTANT]
> If you add support for a new distribution to this Ansible role, please try to
> find a Docker image that uses this distribution and add it to the list of
> images in [`.github/workflows/ci.yml`][], and, if necessary, update
> [`tests/test.yml`][] to install Ansible's dependencies on containers using
> this image.  Additionally, please add the new image to the list above.
