require "bosh/director"
require "cli"
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

  def create(file)
    dir = File.join(@@nise_bosh.working_directory, 'blobstore')
    FileUtils.mkdir_p(dir)
    saved_file_path = File.join("/tmp", File.basename(file.path))
    FileUtils.cp(file.path, saved_file_path)
    File.basename(saved_file_path)
  end

  def self.set_nise_bosh(nb)
    @@nise_bosh = nb
  end
end

class Bosh::Director::DeploymentPlan::Template
  def download_blob
    # tmp_file will be deleted
    tmp_file = File.join(Dir.tmpdir, "template-#{@name}")
    FileUtils.cp(@@nise_bosh.find_job_template_archive(@name), tmp_file)
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

class Bosh::Director::JobUpdater
  def update
    instances = []
    @job.instances.each do |instance|
      instances << instance if instance.changed?
    end

    update_instances(nil, instances, nil)
  end

  def update_instances(pool, instances, event_log_stage)
    instances.each do |instance|
      Bosh::Director::InstanceUpdater.new(instance, nil, @job_renderer).update
    end
  end
end

class Bosh::Director::InstanceUpdater
  def initialize(instance, event_log_task, job_renderer)
    @instance = instance
    @job_renderer = job_renderer
 end

  def update(options = {})
    @job_renderer.render_job_instance(@instance)
  end
end

class Bosh::Director::JobRenderer
  def render_job_instance(instance)
    rendered_job_instance = @instance_renderer.render(instance.spec)
    configuration_hash = rendered_job_instance.configuration_hash
    rendered_templates_archive = rendered_job_instance.persist(@blobstore)
    instance.configuration_hash = configuration_hash
    instance.template_hashes    = rendered_job_instance.template_hashes
    instance.rendered_templates_archive = rendered_templates_archive
  end
end

class DummyPlatform
  def method_missing(name, *args)
  end
end
