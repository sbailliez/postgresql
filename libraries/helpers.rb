#
# Cookbook:: postgresql
# Library:: helpers
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require_relative '_utils'
require 'securerandom'

module PostgreSQL
  module Cookbook
    module Helpers
      include Utils

      def installed_postgresql_major_version
        pgsql_package = node['packages'].filter { |p| p.match?(/postgresql-?(\d+)?$/) }

        raise 'Unable to determine installed PostgreSQL version' if nil_or_empty?(pgsql_package)

        pgsql_package_version = pgsql_package.first[1].fetch('version').to_i
        Chef::Log.info("Detected PostgreSQL version: #{pgsql_package_version}")

        pgsql_package_version
      end

      def data_dir(version = installed_postgresql_major_version)
        case node['platform_family']
        when 'rhel', 'fedora', 'amazon'
          "/var/lib/pgsql/#{version}/data"
        when 'debian'
          "/var/lib/postgresql/#{version}/main"
        end
      end

      def conf_dir(version = installed_postgresql_major_version)
        case node['platform_family']
        when 'rhel', 'fedora', 'amazon'
          "/var/lib/pgsql/#{version}/data"
        when 'debian'
          "/etc/postgresql/#{version}/main"
        end
      end

      # determine the platform specific service name
      def default_platform_service_name(version = installed_postgresql_major_version)
        if platform_family?('rhel', 'fedora', 'amazon')
          "postgresql-#{version}"
        else
          'postgresql'
        end
      end

      def follower?
        ::File.exist? "#{data_dir}/recovery.conf"
      end

      def initialized?
        return true if ::File.exist?("#{conf_dir}/PG_VERSION")
        false
      end

      def secure_random
        r = SecureRandom.hex
        Chef::Log.debug "Generated password: #{r}"
        r
      end

      def default_server_packages
        case node['platform_family']
        when 'rhel', 'fedora', 'amazon'
          %W(postgresql#{version.delete('.')}-contrib postgresql#{version.delete('.')}-libs postgresql#{version.delete('.')}-server)
        when 'debian'
          %W(postgresql-#{version} postgresql-common)
        end
      end

      def default_client_packages
        case node['platform_family']
        when 'rhel', 'fedora', 'amazon'
          %W(postgresql#{version.delete('.')} postgresql#{version.delete('.')}-libs)
        when 'debian'
          %W(postgresql-client-#{version})
        end
      end

      def dnf_module_platform?
        (platform_family?('rhel') && node['platform_version'].to_i == 8) || platform_family?('fedora')
      end

      # determine the appropriate DB init command to run based on RHEL/Fedora/Amazon release
      # initdb defaults to the execution environment.
      # https://www.postgresql.org/docs/9.5/static/locale.html
      def rhel_init_db_command(new_resource)
        cmd = "/usr/pgsql-#{new_resource.version}/bin/initdb"
        cmd << " --locale '#{new_resource.initdb_locale}'" if new_resource.initdb_locale
        cmd << " -E '#{new_resource.initdb_encoding}'" if new_resource.initdb_encoding
        cmd << " #{new_resource.initdb_additional_options}" if new_resource.initdb_additional_options
        cmd << " -D '#{data_dir(new_resource.version)}'"
      end

      # Given the base URL build the complete URL string for a yum repo
      def yum_repo_url(base_url)
        "#{base_url}/#{new_resource.version}/#{yum_repo_platform_family_string}/#{yum_repo_platform_string}"
      end

      # Given the base URL build the complete URL string for a yum repo
      def yum_common_repo_url
        "https://download.postgresql.org/pub/repos/yum/common/#{yum_repo_platform_family_string}/#{yum_repo_platform_string}"
      end

      # The postgresql yum repos URLs are organized into redhat and fedora directories.s
      # route things to the right place based on platform_family
      def yum_repo_platform_family_string
        platform_family?('fedora') ? 'fedora' : 'redhat'
      end

      # Build the platform string that makes up the final component of the yum repo URL
      def yum_repo_platform_string
        platform = platform?('fedora') ? 'fedora' : 'rhel'
        release = platform?('amazon') ? '7' : '$releasever'
        "#{platform}-#{release}-$basearch"
      end

      # On Amazon use the RHEL 7 packages. Otherwise use the releasever yum variable
      def yum_releasever
        platform?('amazon') ? '7' : '$releasever'
      end

      # Fedora doesn't seem to know the right symbols for psql
      def psql_environment
        return {} unless platform?('fedora')
        { LD_LIBRARY_PATH: '/usr/lib64' }
      end

      # Generate a password if the value is set to generate.
      def postgres_password(new_resource)
        new_resource.password == 'generate' ? secure_random : new_resource.password
      end
    end
  end
end
