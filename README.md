[![Build Status](https://travis-ci.org/nttlabs/nise_bosh.png?branch=master)](https://travis-ci.org/nttlabs/nise_bosh)
[![Code Climate](https://codeclimate.com/github/nttlabs/nise_bosh.png)](https://codeclimate.com/github/nttlabs/nise_bosh)

# Nise BOSH v2

## What's this?

Nise BOSH is a lightweight BOSH emulator. You can easily install multiple BOSH packages on your servers with Nise BOSH commands. 'Nise' means 'Pseudo' in Japanese.

## Quick Links

* [Cloud Foundry v2 installer with Nise BOSH](https://github.com/yudai/cf_nise_installer)
  * One liner CF installer for both local machines and Vagrant
* [Nise BOSH Vagrant](https://github.com/BrianMMcClain/nise-bosh-vagrant) 
  * Vagrant integration by BrianMMcClain. See also: "[Introducing Nise-bosh-vagrant](http://catdevrandom.me/blog/2013/05/21/introducing-nise-bosh-vagrant/)"
* [Step by Step Guide on Cloud Foundry Blog (v1)](http://blog.cloudfoundry.com/2013/04/15/ntt-contributes-nise-bosh-a-tool-to-speed-up-bosh-development/)
* [Architecture Guide (v1)](http://www.slideshare.net/i_yudai/nise-bosh-in-action)


## Requirements

* Ubuntu 10.04, 12.04
 * Ubuntu 10.04 64bit is recommended when you install cf-release jobs.
* Ruby 1.9.3-p448 or higher
* Bundler

## How to use

("[Cloud Foundry v2 installer with Nise BOSH](https://github.com/yudai/cf_nise_installer)" is available for Cloud Foundry users)

### Install required gems

You can install the required gems to execute Nise BOSH commands with bundler.

Run the command below:

    bundle install

### Release repository

Nise BOSH requires a clone of the 'release' repository you want to install (e.g. cf-release for Cloud Foundry). Clone the repository with the `git` command.

    git clone git@github.com:cloudfoundry/cf-release.git

### Build a release (Optional)

You can skip this section when you have no modification to the release repository. The latest `final` release will be used automatically.

When you modify the cloned repository, you need to create a `dev` (or `final`) release to install it with Nise BOSH.

If you have not installed BOSH CLI. You can install it with the `gem` command.

    gem install bosh_cli

Then build a release, this might take several minutes at the first run.

    bosh create release

You will be asked the name of the build, input the preferred name such as 'appcloud'.

Note that when your release directory is `dirty` (uncommitted files exist), you need to execute 'bosh create release ' with "--force" option.

### Describe a deployment manifest

Nise-BOSH requires a [deployment manifest](http://docs.cloudfoundry.org/bosh/deployment-manifest.html), which contains the configuration of your release. The Nise-BOSH's manifest file is compatible with, or a subset of, BOSH's manifest format.

You can find an example at [Cloud foundry docs](http://docs.cloudfoundry.org/deploying/vsphere/bosh-example-manifest.html).

    ---
    jobs:
      - name: devbox
        template: dea_next

    properties:
      domain: vcap.me
    
      networks:
        apps: default
        management: default
    
      nats:
        user: nats
        password: nats
        address: 127.0.0.1
        port: 4222
    
      dea_next:
        streaming_timeout: 60
        memory_mb: 4096
        memory_overcommit_factor: 1
        disk_mb: 32000
        disk_overcommit_factor: 1
        num_instances: 30

### Run

Run `nise-bosh` command. You may want to run with 'sudo' and/or 'bundle exec'

    ./bin/nise-bosh <path_to_release_repository> <path_to_deploy_manifest> <job_name>

Example:

    sudo env PATH=$PATH bundle exec ./bin/nise-bosh ~/cf-release ~/deploy.conf devbox

### Initialize the environment

You need to install and create the required apt packages and users on your environment to execute certain job processes from cf-release. The original BOSH sets up the environment using a stemcell, but Nise-BOSH does not support it. You can simulate a stemcell-like environment on your server by executing the `bin/init` script.

    sudo ./bin/init

This script runs the minimal (sometimes insufficient) commands extracted from the stemcell-builder stages.

### Launch processes

Once installation is complete, you can launch job processes by the `monit` command installed by the `bin/init` script.

    sudo /var/vcap/bosh/bin/monit start all

## Command line options

### '-y': Assume yes as an answer to all prompts

Nise-BOSH does not ask any prompts.

### '-f': Force install packages

By default, Nise-BOSH does not re-install packages that are already installed. This option forces Nise BOSH to re-install all packages.

### '-d': Install directory

Nise-BOSH installs packages into this directory. The default value is `/var/vcap`. Be sure to change this value because some packages given by cf-release have hard-coded directory names in their packaging scripts and template files.

### '--working-dir': Temporary working directory

Nise-BOSH uses the given directory to run packaging scripts. The default value is `/tmp/nise_bosh`.

### '-t': Install template files only

Nise-BOSH does not install the required packages for the given job. Nise-BOSH only fills template files for the given job and writes them out to the install directory.

### '-r': Release file

Nise-BOSH uses the given release file for deploying. By default, Nise BOSH automatically detects the newest release file.

### '-n': IP address for the host

Nise-BOSH assumes the IP address of your host using 'ip' command by default. You can overwrite the value by this option.

### '-i': Index number for the host

Nise-BOSH assumes the index number of your host is assigned as 0 by default. When you install the same job on multiple hosts, you can set the index number with this option. The value "spec.index" in the job template files is replaced with this value.

### '-p': Install specific packages

Nise-BOSH installs the given packages, not a job. When this option is chosen, the file path for the deploy manifest file must be omitted.

Example:

    sudo env PATH=$PATH bundle exec ./bin/nise-bosh -p ~/cf-release_interim dea_jvm dea_ruby

### '--no-dependency': Install no dependency packages

Nise-BOSH does not install dependency packages. This option must be used with '-c' option.

### '-a': Create an archive file for a job

Nise-BOSH aggregates the packages and the index file required to install the given job and creates an archive file that includes them. This behavior is similar to 'bosh create release --with-tarball', but the generated archive file contains the minimum packages to install the given job.

## Appendix

### stemcell_base.tar.gz builder

You can generate stemcell_base.tar.gz for the rootfs of Warden containers by the 'gen-stemcell' command. Default config files are found in the config directory. Before executing, change the password for containers in config/stemcell-settings.sh.

    sudo ./bin/gen-stemcell [<output_filename_or_directory>]

The generated archive file is placed on /var/vcap/stemcell_base.tar.gz by default. You can change the path and other behavior by the giving command line options shown by the '--help' option.

### init

You can install basic apt packages and create users for the BOSH stemcell with this command.

### bget

You can download objects from the blobstore for cf-release by using the 'bget' command.

    ./bin/bget -o <output_file_name> <object_id>

## Known incompatibility

Nise BOSH has some kwon incompatibility with BOSH.

* File permissions
  * Nise BOSH does not harden the file permisison of the files such as /dev/shm/, /var/lock, /data/vcap/data, /data/vcap/store, and /tmp.
    * Performed by [bosh_agent](https://github.com/cloudfoundry/bosh/blob/master/bosh_agent/lib/bosh_agent/bootstrap.rb)
* Packaging-time dependencies
  * Nise BOSH keeps packaging-time depended packages (listed in the spec of packages) after installation

## License

Apache License Version 2.0

The original BOSH is developed by VMware, inc. and distributed under Apache License Version 2.0.

## Other resources

* [BOSH](https://github.com/cloudfoundry/bosh)
 * The original tool chain
 * Recommended when IaaS support is available
* [cf-vagrant-installer](https://github.com/Altoros/cf-vagrant-installer)
 * Vagrant installer for Cloud Foundry v2
