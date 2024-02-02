require 'vagrant'
require File.expand_path('plugins/guests/linux/guest', Vagrant.source_root)

module VagrantPlugins
  module LibreELEC
    class Guest < VagrantPlugins::GuestLinux::Guest
      # `VagrantPlugins::GuestLinux::Guest#detect?` tests the value of this
      # constant against (among other things) the value of the `ID` variable in
      # `/etc/os-release`.  For LibreELEC, the correct value is the string
      # "libreelec".
      GUEST_DETECTION_NAME = 'libreelec'.freeze
    end
  end
end
