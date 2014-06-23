require 'yaml'
require 'psych'
require 'erb'

module NiseBosh
  class Builder
    def initialize(options, logger)
      check_ruby_version
      initialize_options(options)
      initialize_release_file
      initialize_depoy_manifest

      @logger = logger
      @index ||=  @options[:index] || 0

      # injection
      Bosh::Agent::Configuration.set_nise_bosh(self)
      Bosh::Agent::Message::Apply.set_nise_bosh(self)
      Bosh::Director::DeploymentPlan::Template.set_nise_bosh(self)
    end

    attr_reader :logger
    attr_reader :options
    attr_reader :release
    attr_reader :release_file

    def check_ruby_version
      if RUBY_VERSION < '1.9.0'
        raise "Ruby 1.9.0 or higher is required. Your Ruby version is #{RUBY_VERSION}"
      end
    end

    def ip_address
      @ip_address ||= @options[:ip_address] || %x[ip -4 -o address show].match('inet ([\d.]+)/.*? scope global') { |md| md[1] }
    end

    def initialize_options(options)
      @options = options
      @options[:repo_dir] = File.expand_path(@options[:repo_dir])
      raise "Release repository does not exist." unless File.exists?(@options[:repo_dir])
    end

    def initialize_release_file
      config_dir = File.join(@options[:repo_dir], "config")

      final_config_path = File.join(config_dir, "final.yml")
      final_name = File.exists?(final_config_path) ? YAML.load_file(final_config_path)["final_name"] : nil
      final_index_path = File.join(@options[:repo_dir], "releases", "index.yml")
      final_index = File.exists?(final_index_path) ? YAML.load_file(final_index_path)["builds"] : {}

      dev_config_path = File.join(config_dir, "dev.yml")
      dev_name = File.exists?(dev_config_path) ? YAML.load_file(dev_config_path)["dev_name"] : nil
      dev_index_path = File.join(@options[:repo_dir], "dev_releases", "index.yml")
      dev_index = File.exists?(dev_index_path) ? YAML.load_file(dev_index_path)["builds"] : {}

      if @options[:release_file].nil? && final_index.size == 0 && dev_index.size == 0
        raise "No release index found!\nTry `bosh create release` in your release repository."
      end
      newest_release = get_newest_release(final_index.merge(dev_index).map {|k, v| v["version"]})

      begin
        @release_file = @options[:release_file] ||
          (newest_release.include?("dev") ?
          File.join(@options[:repo_dir], "dev_releases", "#{dev_name}-#{newest_release}.yml"):
          File.join(@options[:repo_dir], "releases", "#{final_name}-#{newest_release}.yml"))
        @release = YAML.load_file(@release_file)
      rescue
        raise "Faild to load release file!"
      end
    end

    def get_newest_release(index)
      sort_release_version(index).last
    end

    def sort_release_version(index)
      result = index.map {|v| v.to_s.split("-")}.sort do |(v1, v1_dev) , (v2, v2_dev)|
        (v1, v1_frc) = v1.split("."); (v2, v2_frc) = v2.split(".")
        v1_frc ||= "0"; v2_frc ||= "0"
        (v1 != v2) ? v1.to_i <=> v2.to_i :
          (v1_frc != v2_frc) ? v1_frc.to_i <=> v2_frc.to_i :
          (v1_dev == v2_dev) ? raise("Invalid index file") :
          (v2_dev == "dev") ? 1 :
          -1
      end
      result.map {|v| v[1] ? v.join("-") : v[0]}
    end

    def initialize_depoy_manifest()
      if @options[:deploy_manifest]
        begin
          @deploy_manifest = YAML.load_file(@options[:deploy_manifest])
        rescue
          raise "Manifest file not found!"
        end

        # default values
        @deploy_manifest["name"] ||= "dummy"
        @deploy_manifest["releases"] ||= [{"name" => @release["name"], "version" => @release["version"]}]
        @deploy_manifest["networks"] ||= [{"name" => "default", "subnets" => [{"range" => "#{ip_address}/16", "cloud_properties" => {"name" => "DUMMY_VLAN"}, "static" => ["#{ip_address} - #{ip_address}"]}]}]
        @deploy_manifest["compilation"] ||= {"workers" => 1, "network" => "default", "cloud_properties" => {}}
        @deploy_manifest["update"] ||= {"canaries" => 1, "max_in_flight" => 1, "canary_watch_time" => "1-2", "update_watch_time" => "1-2"}
        @deploy_manifest["resource_pools"] ||= [{"name" => "default", "size" => 9999, "cloud_properties" => {}, "stemcell"=> {"name" => "dummy", "version" => "dummy"}, "network" => "default"}]
        # complete missing values
        @deploy_manifest["jobs"].each do |job_spec|
          job_spec["resource_pool"] ||= "default"
          job_spec["instances"] ||= 1
          job_spec["networks"] ||= [{"name" => "default"}]
        end
      end
    end

    def initialize_environment
      initialize_directories
      initialize_monit
    end

    def initialize_directories
      %w(bosh jobs packages monit store shared).each do |dir|
        FileUtils.mkdir_p(File.join(@options[:install_dir], dir))
      end
      FileUtils.chown('vcap', 'vcap', File.join(@options[:install_dir], "shared"))

      Bosh::Agent::Bootstrap.new.setup_data_sys
    end


    def initialize_monit()
      Bosh::Agent::Monit.setup_monit_user
      Bosh::Agent::Monit.setup_alerts
    end

    def archive(job, archive_name = nil)
      cleanup_working_directory()
      release_dir = File.join(@options[:working_dir], "release")
      FileUtils.mkdir_p(release_dir)

      resolve_dependency(job_all_packages(job)).each do |package|
        file = find_package_archive(package)
        copy_release_file_relative(file, release_dir)
        copy_release_file_relative(File.join(File.dirname(file), "index.yml"), release_dir)
      end

      # include all job templates
      job_template_definitions.each do |job_template_definition|
        file = find_job_template_archive(job_template_definition["name"])
        copy_release_file_relative(file, release_dir)
        copy_release_file_relative(File.join(File.dirname(file), "index.yml"), release_dir)
      end

      FileUtils.cp(@release_file, File.join(@options[:working_dir], "release.yml"))

      default_name = "#{@release["name"]}-#{job}-#{@release["version"]}.tar.gz"
      out_file_name = archive_name ? (File.directory?(archive_name) ? File.join(archive_name, default_name) : archive_name ) : default_name
      system("tar -C #{@options[:working_dir]} -cvzf #{out_file_name} . > /dev/null")
    end

    def cleanup_working_directory()
      FileUtils.rm_rf(@options[:working_dir])
      FileUtils.mkdir_p(@options[:working_dir])
    end

    def copy_release_file_relative(from_path, to_release_dir)
      to_path = File.join(to_release_dir, from_path[@options[:repo_dir].length..-1])
      FileUtils.mkdir_p(File.dirname(to_path))
      FileUtils.cp_r(from_path, to_path)
    end

    def job_template_definitions()
      @release["jobs"]
    end

    def job_template_definition(name)
      find_by_name(@release["jobs"], name)
    end

    def package_definition(name)
      find_by_name(@release["packages"], name)
    end

    def install_packages(packages, no_dependency = false)
      unless no_dependency
        @logger.info("Resolving package dependencies...")
        resolved_packages = resolve_dependency(packages)
      else
        resolved_packages = packages
      end
      @logger.info("Installing the following packages: ")
      resolved_packages.each do |package|
        @logger.info(" * #{package}")
      end
      resolved_packages.each do |package|
        @logger.info("Installing package #{package}")
        install_package(package)
      end
    end

    def install_package(package)
      current_version = nil

      install_dir = File.join(@options[:install_dir], "packages", package)
      if File.exists?(install_dir)
        link_dest = File.readlink(install_dir)
        current_version = link_dest.split('/').last
      end

      if @options[:force_compile] || current_version != package_definition(package)["version"].to_s
        run_packaging(package)
      else
        @logger.info("The same version of the package is already installed. Skipping")
      end
    end

    def run_packaging(name)
      @logger.info("Running the packaging script for #{name}")
      package = find_by_name(@release["packages"], name)
      FileUtils.rm_rf(File.join(@options[:install_dir], "packages", name))
      Bosh::Agent::Message::CompilePackage.process([
          "dummy_blob",
          package["sha1"],
          name,
          package["version"],
          []
        ])
    rescue Bosh::Agent::MessageHandlerError => e
      @logger.info("An error occurred while compiling #{name}")
      @logger.info(e.blob)
      raise e
    end

    def resolve_dependency(packages, resolved_packages = [], trace = [])
      packages.each do |package|
        next if resolved_packages.include?(package)
        t = Array.new(trace) << package
        deps = package_definition(package)["dependencies"] || []
        unless (deps & t).empty?
          raise "Detected a cyclic dependency"
        end
        resolve_dependency(deps, resolved_packages, t)
        resolved_packages << package
      end
      return resolved_packages
    end

    def package_exists?(package)
      File.exists?(File.join(@options[:repo_dir], "packages", package))
    end

    def install_job(job_name, template_only = false)
      job_spec = find_by_name(@deploy_manifest["jobs"], job_name)
      job_spec["networks"][0]["static_ips"] ||= [ip_address]

      deployment_plan = Bosh::Director::DeploymentPlan::Planner.parse(@deploy_manifest, Bosh::Director::EventLog::Log.new, {})
      deployment_plan_compiler = Bosh::Director::DeploymentPlan::Assembler.new(deployment_plan)
      deployment_plan_compiler.bind_properties
      deployment_plan_compiler.bind_instance_networks

      target_job = find_by_name(deployment_plan.jobs, job_name)

      Bosh::Director::JobUpdaterFactory.new(Bosh::Director::App.instance.blobstores.blobstore).new_job_updater(deployment_plan, target_job).update
      apply_spec = target_job.instances[0].spec
      apply_spec["index"] = @index

      unless template_only
        install_packages(target_job.send("run_time_dependencies"))
      end

      Bosh::Agent::Message::Apply.process([apply_spec])
    end

    def job_template_spec(job_template_name)
      @job_template_spec ||= {}
      @job_template_spec[@job_template_spec] ||=
        YAML.load(`tar -Oxzf #{find_job_template_archive(job_template_name)} ./job.MF`)
    end

    def job_templates(job_name)
      templates = find_by_name(@deploy_manifest["jobs"], job_name)["template"]
      templates = [templates] if templates.is_a? String
      templates
    end

    def job_template_packages(job_template_name)
      job_template_spec(job_template_name)["packages"]
    end

    def job_all_packages(job_name)
      job_templates(job_name).inject([]) { |i, template|
        i += job_template_packages(template)
      }.uniq
   end

    def job_exists?(name)
      !find_by_name(@deploy_manifest["jobs"], name).nil?
    end

    def find_job_template_archive(name)
      @release_blobs ||= File.exist?(File.join(@options[:repo_dir], "config")) ? Bosh::Cli::Release.new(@options[:repo_dir]).blobstore : nil
      @release_compiler ||= Bosh::Cli::ReleaseCompiler.new(@release_file, @release_blobs, [], @options[:repo_dir])
      @release_compiler.find_job(OpenStruct.new(job_template_definition(name)))
    end

    def find_package_archive(name)
      @release_blobs ||= File.exist?(File.join(@options[:repo_dir], "config")) ? Bosh::Cli::Release.new(@options[:repo_dir]).blobstore : nil
      @release_compiler ||= Bosh::Cli::ReleaseCompiler.new(@release_file, @release_blobs, [], @options[:repo_dir])
      @release_compiler.find_package(OpenStruct.new(package_definition(name)))
    end

    def find_by_name(set, name)
      if set.is_a? Array
        index = set.index do |item|
          (item.respond_to?("name") ?
            item.name :
            (item["name"] || item[:name])
          ) == name
        end
      end
      if index.nil?
        nil
      else
        set[index]
      end
    end

  end
end
