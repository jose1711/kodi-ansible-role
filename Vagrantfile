require_relative 'vagrant/lib/vagrant/libreelec/plugin'

# All boxes used below support libvirt; the LibreELEC and OSMC boxes *only*
# support libvirt.
ENV['VAGRANT_DEFAULT_PROVIDER'] = 'libvirt'

# If possible, tie on-demand box building to box addition events; otherwise,
# perform builds on `vagrant up`.
def trigger_box_build(config, &block)
  if Vagrant.version?(">= 2.4.0") || ENV.fetch('VAGRANT_EXPERIMENTAL', '').split(/,/).include?('typed_triggers')
    config.trigger.before(%I[Vagrant::Action::Builtin::BoxAdd Vagrant::Action::Building::HandleBox], type: :action, &block)
  else
    config.trigger.before(:up, &block)
  end
end

Vagrant.configure(2) do |config|
  config.vm.provider :libvirt do |domain|
    # Listen on all addresses
    domain.graphics_ip = '::'
  end

  config.vm.define :alpine do |alpine|
    alpine.vm.box = 'generic/alpine319'
  end

  config.vm.define :archlinux do |archlinux|
    archlinux.vm.box = 'archlinux/archlinux'
  end

  config.vm.define :debian do |debian|
    debian.vm.box = 'generic/debian12'
  end

  config.vm.define :ubuntu do |ubuntu|
    ubuntu.vm.box = 'generic/ubuntu2204'
  end

  config.vm.define :libreelec do |libreelec|
    box = File.expand_path('tmp/libreelec/LibreELEC-Generic.x86_64-11.0.6.box', __dir__)

    trigger_box_build(libreelec) do |t|
      t.name = 'Create LibreELEC box'
      t.info = "Ensuring that the LibreELEC box at #{box.inspect} exists"
      unless File.exist?(box)
        t.run = {
          path: File.expand_path('scripts/create-libreelec-box', __dir__),
          args: [box],
        }
      end
    end

    libreelec.vm.box_url = "file://#{box}"
    libreelec.vm.box = 'libreelec'
  end

  config.vm.define :osmc do |osmc|
    box = File.expand_path('tmp/osmc/OSMC_TGT_rbp4_20240205.box', __dir__)

    trigger_box_build(osmc) do |t|
      t.name = 'Create OSMC box'
      t.info = "Ensuring that the OSMC box at #{box.inspect} exists"
      t.warn = <<~WARN.gsub(/(?<!^)\n/, ' ')
        The `osmc` box's Vagrantfile defines a Vagrant trigger that installs a
        custom kernel and initial ramdisk to a location accessible to the libvirt daemon.

        This trigger *must* run in order to boot machines using the `osmc` box.

        A bug in Vagrant prevents triggers defined in a box's Vagrantfile from
        running when the box is first added; see https://github.com/hashicorp/vagrant/issues/11901.

        If your OSMC virtual machine hangs upon boot, or if Vagrant crashes
        bringing up the OSMC virtual machine, please try running `vagrant up` a
        second time, as Vagrant will then properly execute the `up` trigger
        mentioned above.
      WARN
      unless File.exist?(box)
        t.run = {
          path: File.expand_path('scripts/create-osmc-box', __dir__),
          args: [box],
        }
      end
    end

    osmc.vm.box_url = "file://#{box}"
    osmc.vm.box = 'osmc'
  end

  config.vm.provision :ansible, type: 'ansible' do |ansible|
    ansible.playbook = 'tests/test.yml'
    ansible.verbose = 'vv'

    # Vagrant uses the `--sudo` flag when `ansible.become` is enabled;
    # evidently Ansible no longer supports `--sudo`.
    #ansible.become = true
    ansible.raw_arguments = %w[--become]
  end
end
