require "nise_bosh"
require 'logger'
require 'yaml'
require 'spec_helper'

describe NiseBosh do
  include_context "default values"

  let(:options) {
    { :repo_dir => release_dir,
      :install_dir => install_dir,
      :deploy_manifest => deploy_manifest,
      :working_dir => working_dir}
  }
  let(:logger) { Logger.new("/dev/null") }

  let(:nb) {
    NiseBosh::Builder.new(options, logger)
  }

  before(:each) do
    setup_directory(working_dir)
    setup_directory(install_dir)
    nb.initialize_environment()
  end

  describe "#new" do
    it "should not raise an error when repo_dir exists" do
      expect { NiseBosh::Builder.new(options, logger) }.to_not raise_error
    end

    it "should raise an error when repo_dir does not exist" do
      options[:repo_dir] = "/not/exist"
      expect { NiseBosh::Builder.new(options, logger) }.to raise_error
    end

    it "should raise an error when repo_dir does have no release index" do
      expect do
        NiseBosh::Builder.new(options.merge({:repo_dir => File.join(File.expand_path("."), "spec", "assets", "release_noindex")}), logger)
      end.to raise_error("No release index found!\nTry `bosh create release` in your release repository.")
    end
  end

  describe "#run_packaging" do
    it "should create the install directory and run the packaging script" do
      nb.run_packaging(package[:name])
      expect_contents(package_file_path(package)).to eq(package[:file_contents])
    end

    it "should raise an error when packaging script fails" do
      expect { nb.run_packaging("fail_packaging") }.to raise_error
    end
  end

  describe "#resolve_dependency" do
    it "should resolve linear dependencies" do
      expect(nb.resolve_dependency(%w{tako kaito})).to eq(%w{miku luca tako kaito})
    end

    it "should resolve part-and-rejoin dependencies" do
      expect(nb.resolve_dependency(%w{meiko})).to eq(%w{miku luca tako meiko})
    end

    it "should raise an error when detects a cyclic dependency" do
      nb = NiseBosh::Builder.new(options.merge({:release_file => File.join(File.expand_path("."), "spec", "assets", "release_cyclic_dependency.yml")}), logger)
      expect { nb.resolve_dependency(%w{ren}) }.to raise_error
    end
  end

  describe "#install_package" do
    let(:package_dir) { File.join(install_dir, "packages", package[:name]) }
    let(:link_dest_dir) { File.join(install_dir, "data", "packages", package[:name], package[:version]) }

    it "should install the given package" do
      nb.install_package(package[:name])
      expect_contents(package_file_path(package)).to eq(package[:file_contents])
      expect(File.readlink(package_dir)).to eq(link_dest_dir)
    end

    it "should not install the given package when the package is already installed" do
      nb.install_package(package[:name])
      expect_contents(package_file_path(package)).to eq(package[:file_contents])
      expect(File.readlink(package_dir)).to eq(link_dest_dir)
      FileUtils.rm_rf(package_file_path(package))
      expect_file_exists(package_file_path(package)).to eq false
      nb.install_package(package[:name])
      expect_file_exists(package_file_path(package)).to eq false
      expect(File.readlink(package_dir)).to eq(link_dest_dir)
    end

    it "should install the given package even if the package is already installed when force_compile option is true" do
      nb.install_package(package[:name])
      expect_contents(package_file_path(package)).to eq(package[:file_contents])
      expect(File.readlink(package_dir)).to eq(link_dest_dir)
      FileUtils.rm_rf(package_file_path(package))
      expect_file_exists(package_file_path(package)).to eq false
      force_nb = NiseBosh::Builder.new(options.merge({:force_compile => true}), logger)
      force_nb.install_package(package[:name])
      expect_contents(package_file_path(package)).to eq(package[:file_contents])
      expect(File.readlink(package_dir)).to eq(link_dest_dir)
    end
  end

  describe "#install_packages" do
    let(:target_packages) { %w{meiko kaito tako} }
    let(:related_packages) { %w{luca} }

    it "should install all related packages" do
      nb.install_packages(target_packages)
      (target_packages + related_packages).each do |package|
        expect_contents(install_dir, "packages", package, "dayo").to eq("tenshi\n")
      end
      expect_contents(package_file_path(package)).to eq(package[:file_contents])
    end

    it "should install only given packages when given no_dependency" do
      nb.install_packages(target_packages, true)
      target_packages.each do |package|
        expect_contents(install_dir, "packages", package, "dayo").to eq("tenshi\n")
      end
      related_packages do |package|
        expect_file_exists(install_dir, "packages", package).to eq false
      end
    end
  end

  describe "#install_job" do
    def check_templates
      expect_contents(install_dir, "jobs", "angel", "config", "miku.conf")
        .to eq("tenshi\n0\n#{current_ip}\n")
      expect_contents(install_dir, "monit", "job", job_monit_file)
        .to eq("monit mode manual")
    end

    it "should install packags and generate required files from template files" do
      nb.install_job("legna")
      expect_contents(install_dir, "packages", "miku", "dayo").to eq("miku #{package[:version]}\n")
      expect_contents(install_dir, "packages", "luca", "dayo").to eq("tenshi\n")
      check_templates
      expect_directory_exists(install_dir, "data", "packages").to eq true
    end

    it "should not install packags and only generate required files from template files when template_only given" do
      nb.install_job("legna", true)
      expect_file_exists(install_dir, "packages", "miku", "dayo").to eq false
      expect_file_exists(install_dir, "packages", "luca", "dayo").to eq false
      check_templates
    end

    it "should fill templates with given IP address and index number, and save file" do
      nb = NiseBosh::Builder.new(options.merge({:ip_address => "39.39.39.39", :index => 39}), logger)
      nb.install_job("legna")
      expect_contents(install_dir, "jobs", "angel", "config", "miku.conf")
        .to eq("tenshi\n39\n39.39.39.39\n")
    end

    it "should keep existing monit files only when the option given" do
      yellow_monit = File.join(install_dir, "monit", "job", "0000_yellows.yellows.monitrc")
      nb.install_job("legna")
      nb = NiseBosh::Builder.new(options, logger)
      nb.install_job("yellows")
      expect_file_exists(install_dir, "monit", "job", job_monit_file).to eq false
      expect_contents(yellow_monit).to eq("yellow_monit mode manual")
      nb = NiseBosh::Builder.new(options.merge({:keep_monit_files => true}), logger)
      nb.install_job("legna")
      check_templates
      expect_file_exists(yellow_monit).to eq true
   end
  end

  describe "#sort_release_version" do
    it "should sort version numbers" do
      expect(nb.sort_release_version(%w{1 2 1.1 1.1-dev 33 2.1-dev 33-dev 2.1}))
        .to eq(%w{1 1.1-dev 1.1 2 2.1-dev 2.1 33-dev 33})
    end
  end

  describe "#archive" do
    before do
      @archive_dir = File.join(tmp_dir, "archive")
      @archive_check_dir = File.join(tmp_dir, "archive_check")
      setup_directory(@archive_dir)
      setup_directory(@archive_check_dir)
    end

    def check_archive_contents(file_name)
      FileUtils.cd(@archive_check_dir) do
        system("tar xvzf #{file_name} > /dev/null")
        expect_to_same(%W{#{options[:repo_dir]} dev_releases #{release_name}-#{release_version}.yml}, [@archive_check_dir, "release.yml"])
        expect_file_exists(@archive_check_dir, "release", ".dev_builds", "jobs", "angel", "1.1-dev.tgz").to eq true
        expect_file_exists(@archive_check_dir, "release", ".dev_builds", "jobs", "yellows", "0.1-dev.tgz").to eq true
        expect_file_exists(@archive_check_dir, "release", ".final_builds", "packages", "luca", "1.tgz").to eq true
        expect_file_exists(@archive_check_dir, "release", ".dev_builds", "packages", "miku", "1.1-dev.tgz").to eq true
      end
    end

    it "create archive in current directory" do
      file_name = File.join(@archive_dir, default_archive_name)
      FileUtils.cd(@archive_dir) do
        nb.archive(success_job, file_name)
        expect(File.exists?(file_name)).to eq true
      end
      check_archive_contents(file_name)
    end

    it "create archive at given file path" do
      file_name = File.join(@archive_dir, "miku.tar.gz")
      nb.archive(success_job, file_name)
      expect(File.exists?(file_name)).to eq true
      check_archive_contents(file_name)
    end

    it "create archive in given directory" do
      file_name = File.join(@archive_dir, default_archive_name)
      nb.archive(success_job, @archive_dir)
      expect(File.exists?(file_name)).to eq true
      check_archive_contents(file_name)
    end
  end

  describe "#job_exists?" do
    it "should return true when given job exists" do
      expect(nb.job_exists?("legna")).to eq true
    end

    it "should return false when given job does not exist" do
      expect(nb.job_exists?("not_exist_job")).to eq false
    end
  end

  describe "#package_exists?" do
    it "should return true when given package exists" do
      expect(nb.package_exists?(package[:name])).to eq true
    end

    it "should return false when given package does not exist" do
      expect(nb.package_exists?("not_exist_package")).to eq false
    end
  end
end
