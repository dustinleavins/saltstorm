# Saltstorm - Fun-Money Betting on the Web
# Copyright (C) 2013  Dustin Leavins
#
# Full license can be found in 'LICENSE.txt'

require 'yaml'

module Settings
  @@default_site_options = {
    path: 'config/site.yml'
  }

  @@default_db_options = {
    path: 'config/database.yml'
  }

  @@default_token_options = {
    path: 'config/secret_token.yml'
  }

  def self.site(environment, options={})
    config_hash = @@default_site_options.merge(options)
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

  def self.db(environment, options={})
    config_hash = @@default_db_options.merge(options)
    return YAML::load_file(config_hash[:path])[environment]
  end

  def self.secret_token(options={})
    config_hash = @@default_token_options.merge(options)
    return YAML::load_file(config_hash[:path])['token']
  end
end
