require "bosh/director"
require "cli"
require "bosh_agent"
require "rspec/mocks"

class Bosh::Director::Config
  def self.cloud
    # dummy
  end

  def self.logger
    @@logger ||= Logger.new("/dev/null")
  end
  def self.event_log
    @@event_log ||= Bosh::Director::EventLog.new
  end

  def self.blobstores
    Bosh::Director::Blobstores.new()
  end

  def self.event_log
    Bosh::Director::EventLog::Log.new
  end
end

class Bosh::Director::Blobstores
  def initialize()
  end
  def blobstore()
    "dummy"
  end
end


class Bosh::Director::DeploymentPlan::Template
  def download_blob
    # tmp_file will be deleted
    tmp_file = File.join(Dir.tmpdir, "template-#{@name}")
    FileUtils.cp(@@nise_bosh.find_job_tempalte_archive(@name), tmp_file)
    tmp_file
  end

  # @return [String]
  def version
    @@nise_bosh.job_template_definition(@name)["version"].to_s
  end

  # @return [String]
  def sha1
    @@nise_bosh.job_template_definition(@name)["sha1"]
  end

  # @return [String]
  def blobstore_id
    "dummy"
  end

  # @return [Array]
  def logs
    {} # dummy
  end

  def properties
    # read the manifest yaml file in the archive
    @job_spec_yaml ||= YAML.load(`tar -Oxzf #{@@nise_bosh.find_job_template_archive(@name)} ./job.MF`)
    @job_spec_yaml["properties"]
  end

  def package_models
    # create dummy models
    @job_spec_yaml["packages"].map { |package_name|
      dummy_model = {
        "name" => package_name,
      }
      def dummy_model.name
        self["name"]
      end
      dummy_model
    }
  end

  def self.set_nise_bosh(nb)
    @@nise_bosh = nb
  end
end


class Bosh::Director::DeploymentPlan::Instance
  def changed?
    true # always true
  end
end

class Bosh::Director::App
  def self.instance
    return Bosh::Director::Config
  end
end

class Bosh::Director::InstanceUpdater
  def initialize(instance, event_log_task, job_renderer)
    @instance = instance
  end

  def update(options = {})
    # nop
  end
end

class DummyPlatform
  def method_missing(name, *args)
  end
end

class Bosh::Agent::Configuration
  def state
    @@state ||= Bosh::Agent::State.new(File.join(self.base_dir, "bosh", "state.yml"))
  end

  def platform
    @@platform ||= DummyPlatform.new
  end

  def base_dir
    @@nise_bosh.options[:install_dir]
  end

  def logger
    @@logger ||= Logger.new("/dev/null")
  end

  def configure
    true
  end

  def self.nise_bosh
    @@nise_bosh
  end

  def self.set_nise_bosh(nb)
    @@nise_bosh = nb
  end
end


class Bosh::Agent::Message::Apply
  def initialize(args)
    @platform = Bosh::Agent::Config.platform

    if args.size < 1
      raise ArgumentError, "not enough arguments"
    end

    @new_spec = args.first
    unless @new_spec.is_a?(Hash)
      raise ArgumentError, "invalid spec, Hash expected, " +
        "#{@new_spec.class} given"
    end

    @old_spec = @new_spec.dup # no problem....
    @old_plan = Bosh::Agent::ApplyPlan::Plan.new(@old_spec)
    @new_plan = Bosh::Agent::ApplyPlan::Plan.new(@new_spec)

    %w(bosh jobs packages monit).each do |dir|
      FileUtils.mkdir_p(File.join(base_dir, dir))
    end
  end

  def apply_packages
    if @new_plan.has_packages?
      # @new_plan.install_packages
    else
      logger.info("No packages")
    end
  end

  def delete_job_monit_files
    return if @@nise_bosh.options[:keep_monit_files]

    dir = File.join(base_dir, "monit", "job")
    logger.info("Removing job-specific monit files: #{dir}")

    # Remove all symlink targets
    Dir.glob(File.join(dir, "*")).each do |f|
      if File.symlink?(f)
        logger.info("Removing monit symlink target file: " +
                        "#{File.readlink(f)}")
        FileUtils.rm_rf(File.readlink(f))
      end
    end

    FileUtils.rm_rf(dir)
  end

  def reload_monit
    # nop
  end

  def self.set_nise_bosh(nb)
    @@nise_bosh = nb
  end
end


class Bosh::Agent::ApplyPlan::Job
  def fetch_bits
    FileUtils.mkdir_p(File.dirname(@install_path))
    FileUtils.mkdir_p(File.dirname(@link_path))

    # no blobstore
    FileUtils.mkdir_p(@install_path)
    Dir.chdir(@install_path) do
      output = `tar --no-same-owner -zxvf #{Bosh::Agent::Configuration.nise_bosh.find_job_template_archive(@template)}`
      raise Bosh::Agent::MessageHandlerError.new(
        "Failed to unpack blob", output) unless $?.exitstatus == 0
    end

    Bosh::Agent::Util.create_symlink(@install_path, @link_path)
  end
end


class Bosh::Agent::Message::CompilePackage
  def initialize(args)
    @blobstore_id, @sha1, @package_name, @package_version, @dependencies = args

    @base_dir = Bosh::Agent::Config.base_dir

    # The maximum amount of disk percentage that can be used during
    # compilation before an error will be thrown.  This is to prevent
    # package compilation throwing arbitrary errors when disk space runs
    # out.
    # @attr [Integer] The max percentage of disk that can be used in
    #     compilation.
    @max_disk_usage_pct = 90
    FileUtils.mkdir_p(File.join(@base_dir, 'data', 'tmp'))

    @logger = Bosh::Agent::Config.logger
    @logger.level = Logger::DEBUG
    @compile_base = "#{@base_dir}/data/compile"
    @install_base = "#{@base_dir}/data/packages"
  end

  def get_source_package
    compile_tmp = File.join(@compile_base, 'tmp')
    FileUtils.mkdir_p compile_tmp
    @source_file = File.join(compile_tmp, @blobstore_id)
    FileUtils.rm @source_file if File.exist?(@source_file)

    FileUtils.cp(Bosh::Agent::Configuration.nise_bosh.find_package_archive(@package_name), @source_file)
  end

  def delete_tmp_files
    [@compile_base].each do |dir| # keep @install_base
      if Dir.exists?(dir)
        FileUtils.rm_rf(dir)
      end
    end
  end


  def clear_log_file(log_file)
    # nop
  end

  def upload
    # nop
  end
end
