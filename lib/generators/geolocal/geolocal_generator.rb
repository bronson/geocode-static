class GeolocalGenerator < Rails::Generators::Base
  source_root File.expand_path('../templates', __FILE__)

  def copy_config_file
    copy_file 'geolocal.rb', 'config/geolocal.rb'
  end
end
