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

  config.vm.provision :ansible, type: 'ansible' do |ansible|
    ansible.playbook = 'tests/test.yml'
    ansible.verbose = 'vv'

    # Vagrant uses the `--sudo` flag when `ansible.become` is enabled;
    # evidently Ansible no longer supports `--sudo`.
    #ansible.become = true
    ansible.raw_arguments = %w[--become]
  end
end
