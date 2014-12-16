require 'optparse'
require 'yaml'
require 'logger'
require 'fileutils'

class Runner
  def initialize(argv)
    @yes = false
    @template_only = false
    @run_mode = :default
    @force_compile = false
    @no_dependency = false
    @version_number_only = false

    @options = {
      :install_dir => File.join("/", "var", "vcap"),
      :working_dir => File.join("/", "tmp", "nise_bosh"),
      :networks => {}
    }

    parse_argv(argv)
  end

  def parse_argv(argv)
    opt = OptionParser.new
    opt.on('-y', 'Assume yes as an answer to all prompts') { |v| @yes = true }
    opt.on('-p', 'Install specific package') { |v| @run_mode = :package }
    opt.on('-t', 'Install only template files') { |v| @template_only = true }
    opt.on('--no-dependency', 'Install no dependeny packages (use with -p option)') { |v| @no_dependency = true }
    opt.on('-a', 'Create an archive for the job') { |v| @run_mode = :archive }
    opt.on('-w', 'Show selected release file') { |v| @run_mode = :show_release_file }
    opt.on('-m', 'Show version number only (with -w option)') { |v| @version_number_only = true }

    opt.on('-d INSTALL_DIR', 'Install directory') { |v| @options[:install_dir] = v }
    opt.on('--working-dir WORKING_DIR', 'Temporary working directory') {|v| @options[:working_dir] = v }
    opt.on('-n IP_ADDRESS', 'IP address for this host') { |v| @options[:ip_address] = v }
    opt.on('-N NETWORK_NAME=IP_ADDRESS', 'Static IP address for this host') do |v|
      unless v.include?('=')
        $stderr.puts(opt.help)
        $stderr.puts("-N option requires NETWORKNAME and IP_ADDRESS")
        exit(1)
      end
      key, value = v.split('=')
      @options[:networks][key] = value
    end
    opt.on('-i INDEX_NUMBER', 'Index number for this host') { |v| @options[:index] = v.to_i }
    opt.on('-r RELEASE_FILE', 'Release file') { |v| @options[:release_file] = v }
    opt.on('-f', 'Force compile') { |v| @options[:force_compile] = true }
    opt.on('--keep-monit-files', 'Keep existing monit files') { |v| @options[:keep_monit_files] = true }

    opt.parse!(argv)
    opt.banner = <<-EOF
       Usage: nise-bosh [OPTION]... RELEASE_REPOSITORY DEPLOY_MANIFEST JOB_NAME
       or:  nise-bosh -a [OPTION]... RELEASE_REPOSITORY DEPLOY_MANIFEST JOB_NAME [OUTPUT_PATH]
       or:  nise-bosh -p [--no-dependency] RELEASE_REPOSITORY PACKAGE_NAME...
       EOF

    @options[:repo_dir] = argv.shift
    if @run_mode == :default && argv.size == 2
      @options[:deploy_manifest] = argv.shift
      @job_name = argv.shift
    elsif @run_mode == :archive && (argv.size == 3 || argv.size == 2)
      @options[:deploy_manifest] = argv.shift
      @job_name = argv.shift
      @output_file = argv.shift
    elsif @run_mode== :package && argv.size >= 1
      @package_names = argv
    elsif @run_mode== :show_release_file && argv.size == 0
      @options[:install_dir] = @options[:working_dir]
    else
      $stderr.puts("Arguments number error!")
      puts(opt.help)
      exit(1)
    end
  end

  def run()
    begin
      @nb = NiseBosh::Builder.new(@options, Logger.new($stdout))
      send("run_#{@run_mode}_mode")
    rescue RuntimeError => e
      $stderr.puts(e.message)
      exit(1)
    end
  end

  def confirm()
    return if @yes
    print("Do you want to continue? [Y/n]")
    input = $stdin.gets.strip!
    unless input == '' || input.upcase == "Y"
      puts("Abort.")
      exit(0)
    end
  end

  def run_default_mode()
    @nb.initialize_environment()

    unless @nb.job_exists?(@job_name)
      raise "Given job does not exist!"
    end

    unless @template_only
      puts("The following templates and packages for job #{@job_name} will be installed.")
      @nb.job_templates(@job_name).each do |template|
        puts("    # #{template}")
        @nb.job_template_packages(template).each do |package|
          puts("        * #{package}")
        end
      end
    else
      puts("Template files for the job #{@job_name} will be installed.")
    end
    confirm()

    @nb.install_job(@job_name, @template_only)
    puts "Done!"
  end

  def run_archive_mode()
    @nb.archive(@job_name, @output_file)
  end

  def run_package_mode()
    @nb.initialize_environment()

    @package_names.each do |package|
      unless @nb.package_exists?(package)
        raise "Given package #{package} does not exist!"
      end
    end

    unless @no_dependency
      packages = @nb.resolve_dependency(@package_names)
    else
      packages = @package_names
    end
    puts("The following packages will be installed:")
    packages.each do |package|
      puts("    * #{package}")
    end
    confirm()

    @nb.install_packages(@package_names, @no_dependency)
    puts "Done!"
  end

  def run_show_release_file_mode()
    if @version_number_only
      puts @nb.release["version"]
    else
      puts @nb.release_file
    end
  end
end
