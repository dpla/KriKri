require 'rdf/isomorphic'
require 'linkeddata'
require 'active_support'
require 'rails_config'
require 'krikri/ldp'
require 'krikri/search_index'

require 'dpla/map'
require 'rdf/marmotta'
require 'oai/client'
require 'rest-client'
require 'edtf'
require 'text'
require 'csv'

require 'resque'

module Krikri
  ##
  # Krikri provides metadata aggregation and enhancement services.
  class Engine < ::Rails::Engine
    isolate_namespace Krikri

    def configure_blacklight!
      return unless File.exist?(Blacklight.solr_file)
      krikri_solr = Krikri::Settings.solr
      Blacklight.solr_config = Blacklight.solr_config.merge(krikri_solr) unless
        krikri_solr.nil?
    end

    # Autoload various classes and modules in lib
    config.autoload_paths += Dir["#{config.root}/lib/**/"]

    config.generators do |g|
      g.test_framework :rspec, :fixture => false
      g.fixture_replacement :factory_girl, :dir => 'spec/factories'
      g.assets false
      g.helper false
    end

    initializer 'settings' do
      conf_path = root.join('config')
      setting_files = [conf_path.join('settings.yml'),
                       conf_path.join('settings', "#{Rails.env}.yml"),
                       conf_path.join('environments', "#{Rails.env}.yml"),
                       conf_path.join('settings.local.yml'),
                       conf_path.join('settings', "#{Rails.env}.local.yml"),
                       conf_path.join('environments', "#{Rails.env}.local.yml")
                      ].map(&:to_s)

      settings_const = Kernel.const_get(RailsConfig.const_name)

      source_paths = settings_const.add_source!('nil')[0..-2].map(&:path)
      source_paths = setting_files + source_paths

      RailsConfig.load_and_set_settings(source_paths)
      Krikri::Settings = Kernel.const_get(RailsConfig.const_name)
    end

    initializer :uri_cache do
      RDF::URI::CACHE_SIZE = 
        (Krikri::Settings['uri_cache_size'] || 1_000_000).to_i.freeze
    end

    initializer :append_migrations do |app|
      unless app.root.to_s == root.to_s
        config.paths['db/migrate'].expanded.each do |exp_path|
          app.config.paths['db/migrate'] << exp_path
        end
      end
    end

    initializer :register_harvesters do
      Krikri::Harvester::Registry
        .register(:oai, Krikri::Harvesters::OAIHarvester)
      Krikri::Harvester::Registry
        .register(:couchdb, Krikri::Harvesters::CouchdbHarvester)

    end

    initializer :rdf_repository do
      Krikri::Repository =
        RDF::Marmotta.new(
          Krikri::Settings['marmotta']['base'],
          { read_timeout: Krikri::Settings['marmotta']['read_timeout'] }
        )
    end

    initializer :blacklight_settings do
      configure_blacklight!
    end

    initializer :aggregation do
      class NamespaceError < RuntimeError
        def initialize(uri)
          super("Tried to get DPLA ID for non-DPLA URI #{uri}")
        end
      end

      DPLA::MAP::Aggregation.class_eval do
        include Krikri::MapCrosswalk
        include Krikri::LDP::RdfSource
        configure :base_uri => Krikri::Settings['marmotta']['item_container']

        def mint_id!(seed = nil)
          set_subject!(mint_id_fragment(seed))
          update_source_resource_subject
        end

        ##
        # Forceably update the subject for the dpla:SourceResource to use a
        # fragment URI. This is necessary because of an issue in
        # ActiveTriples.
        #
        # @see https://github.com/ActiveTriples/ActiveTriples/issues/107
        def update_source_resource_subject
          unless sourceResource.empty?
            sr = get_values(RDF::EDM::aggregatedCHO).first
            orig = sourceResource_ids.first
            # Q: should we have a check like `orig.node?` here?
            sr.set_subject!(rdf_subject / '#sourceResource')
            sr.persist!
            update([self, RDF::EDM::aggregatedCHO, sr])
            delete([orig, nil, nil])
          end
        end

        ##
        # Get the persisted original record for this Aggregation.
        # @return [Krikri::OriginalRecord, nil]
        #
        # @raise [NameError] when the original record is empty or is a blank
        #   node.
        #
        # @raise [Faraday::ConnectionError] when there is a connection problem
        #   with Marmotta.
        def original_record
          raise NameError, no_origrec_message if
            originalRecord.empty? || originalRecord.first.node?
          Krikri::OriginalRecord.load(originalRecord.first.rdf_subject
            .to_s)
        end

        ##
        # @return [String, nil] returns only the final portion of the URI (the 
        #   "local name"), with the `#base_uri` removed. `nil` if this is a node
        #
        # @raise NamespaceError
        def dpla_id
          return nil if node?
          raise NamespaceError, rdf_subject unless id.start_with?(base_uri)

          id.gsub("#{base_uri}/", '')
        end
          
        private

        def local_name_from_original_record
          return nil if originalRecord.empty?
          raise "#{self} has more than one OriginalRecord, cannot source a " \
          "definitive identifier." unless originalRecord.length == 1
          originalRecord.first.rdf_subject.path.split('/').last.split('.').first
        end

        def mint_id_fragment(seed = nil)
          return seed if seed
          # We rely on originalRecord for consistent ID minting, so we have to
          # raise an exception if it's empty or is a blank node; for example,
          # if a mapping failed to map it.
          raise NameError, no_origrec_message if
            originalRecord.empty? || originalRecord.first.node?
          local_name_from_original_record
        end

        def no_origrec_message
          "#{dpla_id} #{no_origrec_cond}"
        end

        def no_origrec_cond
          if originalRecord.empty?
            "has an empty originalRecord"
          else
            "has a blank node for its originalRecord"
          end
        end
      end
    end

    ##
    # Allow the methods in Krikri::ApplicatoinHelper to be accessible by the
    # host application.
    initializer 'krikri.helpers' do |app|
      ActionView::Base.send :include, Krikri::ApplicationHelper
    end
  end
end
