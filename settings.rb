# Saltstorm - Fun-Money Betting on the Web
# Copyright (C) 2013  Dustin Leavins
#
# Full license can be found in 'LICENSE.txt'

require 'yaml'

# Module that retrieves server settings that are dependent on a specific
# environment.
module Settings
  DEFAULT_SITE_OPTIONS = {
    :path => 'config/site.yml'
  }

  DEFAULT_DB_OPTIONS = {
    :path => 'config/database.yml'
  }

  DEFAULT_TOKEN_OPTIONS = {
    :path => 'config/secret_token.yml'
  }

  # Retrieves site options
  def self.site(environment, options={})
    config_hash = DEFAULT_SITE_OPTIONS.merge(options)
    yaml_file = YAML::load_file(config_hash[:path])
    environment_settings = yaml_file[environment]
    common_settings = yaml_file['common']

    if (environment_settings.nil?)
      return common_settings
    elsif (common_settings.nil?)
      return environment_settings
    else
      return common_settings.merge(environment_settings)
    end
  end

  # Retrieves database options
  def self.db(environment, options={})
    config_hash = DEFAULT_DB_OPTIONS.merge(options)
    return YAML::load_file(config_hash[:path])[environment]
  end

  # Retrieves the secret token
  def self.secret_token(options={})
    config_hash = DEFAULT_TOKEN_OPTIONS.merge(options)
    return YAML::load_file(config_hash[:path])['token']
  end
end
