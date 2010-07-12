require File.join(File.dirname(__FILE__), '..', '..', '..', 'test_helper')

class NFSVMActionTest < Test::Unit::TestCase
  setup do
    @klass = Vagrant::Action::VM::NFS
    @app, @env = mock_action_data

    @vm = mock("vm")
    @vm.stubs(:system).returns(mock("system"))
    @env.env.stubs(:host).returns(Vagrant::Hosts::Base.new(@env))
    @env.env.config.vm.network("192.168.55.1")
    @env["vm"] = @vm

    @internal_vm = mock("internal")
    @vm.stubs(:vm).returns(@internal_vm)
  end

  context "with an instance" do
    setup do
      # Kind of dirty but not sure of a way around this
      @klass.send(:alias_method, :verify_settings_real, :verify_settings)
      @klass.any_instance.stubs(:verify_settings)
      @instance = @klass.new(@app, @env)
    end

    context "calling" do
      setup do
        @instance.stubs(:folders).returns([:a])

        [:extract_folders, :export_folders, :mount_folders].each do |meth|
          @instance.stubs(meth)
        end
      end

      should "call the proper sequence and succeed" do
        seq = sequence('seq')
        @instance.expects(:extract_folders).in_sequence(seq)
        @instance.expects(:export_folders).in_sequence(seq)
        @app.expects(:call).with(@env).in_sequence(seq)
        @instance.expects(:mount_folders).in_sequence(seq)
        @instance.call(@env)
      end

      should "not export folders if folders is empty" do
        @instance.stubs(:folders).returns([])

        seq = sequence('seq')
        @instance.expects(:extract_folders).in_sequence(seq)
        @instance.expects(:export_folders).never
        @app.expects(:call).with(@env).in_sequence(seq)
        @instance.expects(:mount_folders).never
        @instance.call(@env)
      end

      should "halt chain if environment error occured" do
        @env.error!(:foo)

        seq = sequence('seq')
        @instance.expects(:extract_folders).in_sequence(seq)
        @instance.expects(:export_folders).in_sequence(seq)
        @app.expects(:call).never
        @instance.call(@env)
      end

      should "not mount folders if an error occured" do
        @app.expects(:call).with() do
          # Use this mark the env as error
          @env.error!(:foo)

          true
        end

        @instance.expects(:mount_folders).never
        @instance.call(@env)
      end
    end

    context "extracting folders" do
      setup do
        @env.env.config.vm.share_folder("v-foo", "/foo", ".", :nfs => true)
        @env.env.config.vm.share_folder("v-bar", "/bar", ".", :nfs => true)
      end

      should "extract the NFS enabled folders" do
        @instance.extract_folders
        assert_equal 2, @instance.folders.length
      end

      should "remove the folders from the original config" do
        @instance.extract_folders
        assert_equal 1, @env["config"].vm.shared_folders.length
        assert @env["config"].vm.shared_folders.has_key?("v-root")
      end
    end

    context "exporting folders" do
      setup do
        @instance.stubs(:folders).returns({})
      end

      should "call nfs_export on the host" do
        @env["host"].expects(:nfs_export).with(@instance.folders)
        @instance.export_folders
      end

      should "error the environment if exception is raised" do
        @env["host"].expects(:nfs_export).raises(Vagrant::Action::ActionException.new(:foo))
        @instance.export_folders
        assert @env.error?
        assert_equal :foo, @env.error.first
      end
    end

    context "mounting folders" do
      setup do
        @instance.stubs(:host_ip).returns("foo")
        @instance.stubs(:folders).returns(["bar"])
      end

      should "mount the folders on the system" do
        @vm.system.expects(:mount_nfs).with(@instance.host_ip, @instance.folders)
        @instance.mount_folders
      end
    end

    context "getting the host IP" do
      setup do
        @network_adapters = []
        @internal_vm.stubs(:network_adapters).returns(@network_adapters)
      end

      def stub_interface(ip)
        interface = mock("interface")
        adapter = mock("adapter")
        adapter.stubs(:host_interface_object).returns(interface)
        interface.stubs(:ip_address).returns(ip)

        @network_adapters << adapter
        interface
      end

      should "return the IP of the first interface" do
        ip = "192.168.1.1"
        stub_interface(ip)

        assert_equal ip, @instance.host_ip
      end

      should "return nil if no IP is found" do
        assert_nil @instance.host_ip
      end
    end

    context "verifying settings" do
      setup do
        @env.env.host.stubs(:nfs?).returns(true)
      end

      should "error environment if host is nil" do
        @env.env.stubs(:host).returns(nil)
        @instance.verify_settings_real
        assert @env.error?
        assert_equal :nfs_host_required, @env.error.first
      end

      should "error environment if host does not support NFS" do
        @env.env.host.stubs(:nfs?).returns(false)
        @instance.verify_settings_real
        assert @env.error?
        assert_equal :nfs_not_supported, @env.error.first
      end

      should "error environment if host only networking is not enabled" do
        @env.env.config.vm.network_options.clear
        @instance.verify_settings_real
        assert @env.error?
        assert_equal :nfs_no_host_network, @env.error.first
      end

      should "be fine if everything passes" do
        @env.env.host.stubs(:nfs?).returns(true)
        @instance.verify_settings_real
        assert !@env.error?
      end
    end
  end
end
