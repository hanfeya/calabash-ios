module Calabash
  module Cucumber

    # Raised when calabash cannot launch the app.
    class LaunchError < RuntimeError
      attr_accessor :error

      def initialize(err)
        self.error= err
      end

      # @!visibility private
      def to_s
        "#{super.to_s}: #{error}"
      end
    end

    # Raised when Calabash cannot find a device based on DEVICE_TARGET
    class DeviceNotFoundError < RuntimeError ; end

    # Launch apps on iOS Simulators and physical devices.
    #
    # ###  Accessing the current launcher from ruby.
    #
    # If you need a reference to the current launcher in your ruby code.
    #
    # `Calabash::Cucumber::Launcher.launcher`
    #
    # This is usually not required, but might be useful in `support/01_launch.rb`.
    #
    # ### Attaching to the current launcher in a console
    #
    # If Calabash already running and you want to attach to the current launcher,
    # use `console_attach`.  This is useful when a cucumber Scenario has failed and
    # you want to query the current state of the app.
    #
    # * **Pro Tip:** Set the `QUIT_APP_AFTER_SCENARIO=0` env variable so calabash
    # does not quit your application after a failed Scenario.
    class Launcher

      require "calabash-cucumber/device"
      require "calabash-cucumber/actions/instruments_actions"
      require "calabash-cucumber/usage_tracker"
      require "calabash-cucumber/dylibs"
      require "calabash-cucumber/environment"
      require "calabash-cucumber/http/http"
      require "run_loop"

      # @!visibility private
      DEFAULTS = {
        :launch_retries => 5
      }

      # @!visibility private
      @@launcher = nil

      # @!visibility private
      @@launcher = nil

      # @!visibility private
      SERVER_VERSION_NOT_AVAILABLE = '0.0.0'

      # @!visibility private
      # Class variable for caching the embedded server version so we only need to
      # check the server version one time.
      @@server_version = nil

      # @!visibility private
      attr_accessor :run_loop

      # @!visibility private
      attr_accessor :actions

      # @!visibility private
      attr_accessor :launch_args

      # @!visibility private
      attr_reader :usage_tracker

      # @!visibility private
      def initialize
        @@launcher = self
      end

      # @!visibility private
      def to_s
        msg = ["#{self.class}"]
        if self.run_loop
          msg << "Log file: #{self.run_loop[:log_file]}"
        else
          msg << "Not attached to instruments."
          msg << "Start your app with `start_test_server_in_background`"
          msg << "If you app is already running, try `console_attach`"
        end
        msg.join("\n")
      end

      # @!visibility private
      def inspect
        to_s
      end

      # @!visibility private
      #
      # Use this method to see if your app is already running.  This is helpful
      # if you have Scenarios that don't require an app relaunch.
      #
      # @raise Raises an error if the server does not respond.
      def ping_app
        Calabash::Cucumber::HTTP.ping_app
      end

      # @!visibility private
      #
      # This Calabash::Cucumber::Device instance is required because we cannot
      # determine the iOS version of physical devices.
      #
      # This device instance can only be created _if the server is running_.
      #
      # We need this instance because we need to know at runtime whether or
      # not to translate touch coordinates in the client or on the server. For
      # iOS >= 8.0 translation is done on the server.  Further, we need a
      # Device instance for iOS < 8 so we can perform the necessary
      # coordinate normalization - based on the device attributes.
      #
      # We also need this instance to determine the default uia strategy.
      #
      # +1 for tools to ask physical devices about attributes.
      def device
        @device ||= lambda do
          _, body = Calabash::Cucumber::HTTP.ensure_connectivity
          endpoint = Calabash::Cucumber::Environment.device_endpoint
          Calabash::Cucumber::Device.new(endpoint, body)
        end.call
      end

      # @!visibility private
      #
      # Legacy API. This is a required method.  Do not remove
      def device=(new_device)
        @device = new_device
      end

      # @!visibility private
      def usage_tracker
        @usage_tracker ||= Calabash::Cucumber::UsageTracker.new
      end

      # @!visibility private
      def actions
        attach if @actions.nil?
        @actions
      end

      # @!visibility private
      # @see Calabash::Cucumber::Core#console_attach
      def self.attach
        l = launcher
        return l if l && l.active?
        l.attach
      end

      # @!visibility private
      # @see Calabash::Cucumber::Core#console_attach
      def attach(options={})
        if Calabash::Cucumber::Environment.xtc?
          raise "This method is not available on the Xamarin Test Cloud"
        end

        default_options = {:http_connection_retry => 1,
                           :http_connection_timeout => 10}
        merged_options = default_options.merge(options)

        self.run_loop = RunLoop::HostCache.default.read

        begin
          Calabash::Cucumber::HTTP.ensure_connectivity(merged_options)
        rescue Calabash::Cucumber::ServerNotRespondingError => _
          device_endpoint = Calabash::Cucumber::Environment.device_endpoint
          RunLoop.log_warn(
%Q[

Could not connect to Calabash Server @ #{device_endpoint}.

If your app is running, check that you have set the DEVICE_ENDPOINT correctly.

If your app is not running, it was a mistake to call this method.

http://calabashapi.xamarin.com/ios/Calabash/Cucumber/Core.html#console_attach-instance_method

Try `start_test_server_in_background`

])

          # Nothing to do except log the problem and exit early.
          return false
        end

        if self.run_loop[:pid]
          self.actions = Calabash::Cucumber::InstrumentsActions.new
        else
          RunLoop.log_warn(
%Q[

Connected to an app that was not launched by Calabash using instruments.

Queries will work, but gestures will not.

])
        end

        self
      end

      # Are we running using instruments?
      #
      # @return {Boolean} true if we're using instruments to launch
      def self.instruments?
        l = launcher_if_used
        return false unless l
        l.instruments?
      end

      # @!visibility private
      def instruments?
        !!(active? && run_loop[:pid])
      end

      # @!visibility private
      def active?
        not run_loop.nil?
      end

      # A reference to the current launcher (instantiates a new one if needed).
      # @return {Calabash::Cucumber::Launcher} the current launcher
      def self.launcher
        @@launcher ||= Calabash::Cucumber::Launcher.new
      end

      # Get a reference to the current launcher (does not instantiate a new one if unset).
      # @return {Calabash::Cucumber::Launcher} the current launcher or nil
      def self.launcher_if_used
        @@launcher
      end

      # Erases a simulator. This is the same as touching the Simulator
      # "Reset Content & Settings" menu item.
      #
      # @param [RunLoop::Device, String] device The simulator to erase.  Can be a
      #  RunLoop::Device instance, a simulator UUID, or a human readable simulator
      #  name.
      #
      # @raise ArgumentError If the simulator is a physical device
      # @raise RuntimeError If the simulator cannot be shutdown
      # @raise RuntimeError If the simulator cannot be erased
      def reset_simulator(device=nil)
        if device.is_a?(RunLoop::Device)
          device_target = device
        else
          device_target = detect_device(:device => device)
        end

        if device_target.physical_device?
          raise ArgumentError,
%Q{
Cannot reset: #{device_target}.

Resetting physical devices is not supported.
}
        end

        RunLoop::CoreSimulator.erase(device_target)
        device_target
      end

      # Launches your app on the connected device or simulator.
      #
      # `relaunch` does a lot of error detection and handling to reliably start the
      # app and test. Instruments (particularly the cli) has stability issues which
      # we workaround by restarting the simulator process and checking that
      # UIAutomation is correctly attaching to your application.
      #
      # Use the `args` parameter to to control:
      #
      # * `:app` - which app to launch.
      # * `:device` - simulator or device to target.
      # * `:reset_app_sandbox - reset the app's data (sandbox) before testing
      #
      # and many other behaviors.
      #
      # Many of these behaviors can be be controlled by environment variables. The
      # most important environment variables are `APP`, `DEVICE_TARGET`, and
      # `DEVICE_ENDPOINT`.
      #
      # @param {Hash} launch_options optional arguments to control the how the app is launched
      def relaunch(launch_options={})
        simctl = launch_options[:simctl] || launch_options[:sim_control]
        instruments = launch_options[:instruments]
        xcode = launch_options[:xcode]

        options = launch_options.clone

        # Reusing SimControl, Instruments, and Xcode can speed up launches.
        options[:simctl] = simctl || Calabash::Cucumber::Environment.simctl
        options[:instruments] = instruments || Calabash::Cucumber::Environment.instruments
        options[:xcode] = xcode || Calabash::Cucumber::Environment.xcode

        self.launch_args = options

        self.run_loop = new_run_loop(options)
        self.actions= Calabash::Cucumber::InstrumentsActions.new

        if !options[:calabash_lite]
          Calabash::Cucumber::HTTP.ensure_connectivity
          # skip compatibility check if injecting dylib
          if !options[:inject_dylib]
            # Don't check until method is rewritten.
            # TODO Enable
            # check_server_gem_compatibility
          end
        end

        usage_tracker.post_usage_async

        # :on_launch to the Cucumber World if:
        # * the Launcher is part of the World (it is not by default).
        # * Cucumber responds to :on_launch.
        self.send(:on_launch) if self.respond_to?(:on_launch)

        self
      end

      # @!visibility private
      def new_run_loop(args)
        last_err = nil
        num_retries = args[:launch_retries] || DEFAULTS[:launch_retries]
        num_retries.times do
          begin
            return RunLoop.run(args)
          rescue RunLoop::TimeoutError => e
            last_err = e
          end
        end

        raise Calabash::Cucumber::LaunchError.new(last_err)
      end

      # @!visibility private
      def stop
        RunLoop.stop(run_loop) if run_loop && run_loop[:pid]
      end

      # Should Calabash quit the app under test after a Scenario?
      #
      # Control this behavior using the QUIT_APP_AFTER_SCENARIO variable.
      #
      # The default behavior is to quit after every Scenario.
      def quit_app_after_scenario?
        Calabash::Cucumber::Environment.quit_app_after_scenario?
      end

      # @!visibility private
      # Extracts server version from the app binary at `app_bundle_path` by
      # inspecting the binary's strings table.
      #
      # @note
      #  SPECIAL: sets the `@@server_version` class variable to cache the server
      #  version because the server version will never change during runtime.
      #
      # @return [String] the server version
      # @param [String] app_bundle_path file path (usually) to the application bundle
      # @raise [RuntimeError] if there is no executable at `app_bundle_path`
      # @raise [RuntimeError] if the server version cannot be extracted from any
      #   binary at `app_bundle_path`
      def server_version_from_bundle(app_bundle_path)
        return @@server_version unless @@server_version.nil?
        exe_paths = []
        Dir.foreach(app_bundle_path) do |item|
          next if item == '.' or item == '..'

          full_path = File.join(app_bundle_path, item)
          if File.executable?(full_path) and not File.directory?(full_path)
            exe_paths << full_path
          end
        end

        if exe_paths.empty?
          RunLoop.log_warn("Could not find executable in '#{app_bundle_path}'")

          @@server_version = SERVER_VERSION_NOT_AVAILABLE
          return @@server_version
        end

        server_version = nil
        exe_paths.each do |path|
          server_version_string = `xcrun strings "#{path}" | grep -E 'CALABASH VERSION'`.chomp!
          if server_version_string
            server_version = server_version_string.split(' ').last
            break
          end
        end

        unless server_version
          RunLoop.log_warn("Could not find server version by inspecting the binary strings table")

          @@server_version = SERVER_VERSION_NOT_AVAILABLE
          return @@server_version
        end

        @@server_version = server_version
      end

      # queries the server for its version.
      #
      # SPECIAL: sets the +@@server_version+ class variable to cache the server
      # version because the server version will never change during runtime.
      #
      # @return [String] the server version
      # @raise [RuntimeError] if the server cannot be reached
      def server_version_from_server
        return @@server_version unless @@server_version.nil?
        ensure_connectivity if self.device == nil
        @@server_version = self.device.server_version
      end

      # @!visibility private
      # Checks the server and gem version compatibility and generates a warning if
      # the server and gem are not compatible.
      #
      # @note  This is a proof-of-concept implementation and requires _strict_
      #  equality.  in the future we should allow minimum framework compatibility.
      #
      # @return [nil] nothing to return
      def check_server_gem_compatibility
        app_bundle_path = self.launch_args[:app]
        if File.directory?(app_bundle_path)
          server_version = server_version_from_bundle(app_bundle_path)
        else
          server_version = server_version_from_server
        end

        if server_version == SERVER_VERSION_NOT_AVAILABLE
          RunLoop.log_warn("Server version could not be found - skipping compatibility check")
          return nil
        end

        server_version = RunLoop::Version.new(server_version)
        gem_version = RunLoop::Version.new(Calabash::Cucumber::VERSION)
        min_server_version = RunLoop::Version.new(Calabash::Cucumber::MIN_SERVER_VERSION)

        if server_version < min_server_version
          msgs = [
            'The server version is not compatible with gem version.',
            'Please update your server.',
            'https://github.com/calabash/calabash-ios/wiki/Updating-your-Calabash-iOS-version',
            "       gem version: '#{gem_version}'",
            "min server version: '#{min_server_version}'",
            "    server version: '#{server_version}'"]
          RunLoop.log_warn("#{msgs.join("\n")}")
        end
        nil
      end

      # @deprecated 0.19.0 - replaced with #quit_app_after_scenario?
      # @!visibility private
      def calabash_no_stop?
        # Not yet.  Save for 0.20.0.
        # RunLoop.deprecated("0.19.0", "replaced with quit_app_after_scenario")
        !quit_app_after_scenario?
      end

      # @!visibility private
      # @deprecated 0.19.0 - no replacement
      def calabash_no_launch?
        RunLoop.log_warn(%Q[
Calabash::Cucumber::Launcher #calabash_no_launch? and support for the NO_LAUNCH
environment variable has been removed from Calabash.  This always returns
true.  Please remove this method call from your hooks.
])
        false
      end

      # @!visibility private
      # @deprecated 0.19.0 - no replacement.
      def default_uia_strategy(launch_args, sim_control, instruments)
        RunLoop::deprecated("0.19.0", "This method has been removed.")
        :host
      end

      # @!visibility private
      # @deprecated 0.19.0 - no replacement
      def detect_connected_device?
        RunLoop.deprecated("0.19.0", "No replacement")
        false
      end

      # @!visibility private
      # @deprecated 0.19.0 - no replacement
      def default_launch_args
        RunLoop.deprecated("0.19.0", "No replacement")
        {}
      end

      # @!visibility private
      # @deprecated 0.19.0 - no replacement
      def discover_device_target(launch_args)
        RunLoop.deprecated("0.19.0", "No replacement")
        nil
      end

      # @!visibility private
      # @deprecated 0.19.0 - no replacement
      def device_target?(options={})
        RunLoop.deprecated("0.19.0", "No replacement")
        detect_device(options).physical_device?
      end

      # @!visibility private
      # @deprecated 0.19.0 - no replacement
      def simulator_target?(options={})
        RunLoop.deprecated("0.19.0", "No replacement")
        detect_device(options).simulator?
      end

      # @!visibility private
      # @deprecated 0.19.0 - no replacement
      def app_path
        RunLoop.deprecated("0.19.0", "No replacement")
        nil
      end

      # @!visibility private
      # @deprecated 0.19.0 - no replacement
      def xcode
        Calabash::Cucumber::Environment.xcode
      end

      # @!visibility private
      # @deprecated 0.19.0 - no replacement
      def ensure_connectivity
        RunLoop.deprecated("0.19.0", "No replacement")
        Calabash::Cucumber::HTTP.ensure_connectivity
      end

      # @!visibility private
      # @deprecated 0.19.0 - no replacement - this method is a no op
      #
      # #relaunch will now send ":on_launch" to the Cucumber World if:
      # * the Launcher is part of the World (it is not by default).
      # * Cucumber responds to :on_launch.
      def calabash_notify(_)
        false
      end

      private

      # @!visibility private
      #
      # A convenience wrapper around RunLoop::Device.detect_device
      def detect_device(options)
        xcode = Calabash::Cucumber::Environment.xcode
        simctl = Calabash::Cucumber::Environment.simctl
        instruments = Calabash::Cucumber::Environment.instruments
        RunLoop::Device.detect_device(options, xcode, simctl, instruments)
      end

      # @!visibility private
      # @return [RunLoop::Device] A RunLoop::Device instance.
      # TODO Remove
      def ensure_device_target
        begin
          @run_loop_device ||= Calabash::Cucumber::Environment.run_loop_device
        rescue ArgumentError => e
          raise Calabash::Cucumber::DeviceNotFoundError,
                %Q[Could not find a matching device in your environment.

#{e.message}

To see what devices are available on your machine, use instruments:

$ xcrun instruments -s devices

]
        end
      end
    end
  end
end

