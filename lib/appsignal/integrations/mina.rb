require 'mina'
require 'mina/hooks'

before_mina :deploy, :'appsignal:mina_deploy'

namespace :appsignal do
  task :mina_deploy do
    env = rails_env
    user = ENV['USER'] || ENV['USERNAME']

    appsignal_config = Appsignal::Config.new(
      ENV['PWD'],
      env,
      fetch(:appsignal_config, {}),
      logger
    )

    if appsignal_config && appsignal_config.active?
      marker_data = {
        :revision => current_revision,
        :repository => repository,
        :user => user
      }

      marker = Appsignal::Marker.new(marker_data, appsignal_config, Appsignal.logger)
      marker.transmit
    end
  end
end