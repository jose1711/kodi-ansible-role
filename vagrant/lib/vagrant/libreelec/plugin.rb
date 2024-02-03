require 'vagrant'

module VagrantPlugins
  module LibreELEC
    class Plugin < Vagrant.plugin(2)
      GUEST_NAME = :libreelec

      name 'LibreELEC guest'
      description 'LibreELEC guest support'

      guest(GUEST_NAME, :linux) do
        require_relative 'guest'
        Guest
      end

      guest_capability(GUEST_NAME, :change_host_name) do
        require File.expand_path('plugins/guests/debian/plugin', Vagrant.source_root)
        VagrantPlugins::GuestDebian::ChangeHostName
      end

      # `/etc/fstab` exists in the LibreELEC guest but is not writable (it's on
      # the squashfs partition).  Stop Vagrant from trying to write to the file
      # by nil-ifying the relevant guest capability.
      guest_capability(GUEST_NAME, :persist_mount_shared_folder) do
        nil
      end
    end
  end
end
