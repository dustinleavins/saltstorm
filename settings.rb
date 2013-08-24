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

    return common_settings.merge(environment_settings)
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
