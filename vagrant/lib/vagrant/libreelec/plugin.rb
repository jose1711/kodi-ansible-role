require 'vagrant'
require File.expand_path('plugins/guests/debian/plugin', Vagrant.source_root)

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
        VagrantPlugins::GuestDebian::ChangeHostName
      end
    end
  end
end
