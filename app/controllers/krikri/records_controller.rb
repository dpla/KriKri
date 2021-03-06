module Krikri
  ##
  # Marshals SolrDocuments for views.
  # Sets default Solr request params for Records.
  #
  # RecordsController inherits from the host application's
  # ApplicationController.  It does not interit from Krikri's
  # ApplicationController.
  class RecordsController < CatalogController
    before_action :authenticate_user!, :set_provider

    self.solr_search_params_logic += [:records_by_provider]

    ##
    # RecordsController has access to views in the following
    # directories:
    #   krikri/records
    #   catalog (defined in Blacklight)
    # It inherits view templates from the host application's
    # ApplicationController.  It uses krikri's application layout:
    layout 'krikri/application'

    configure_blacklight do |config|
      ##
      # Default parameters to send to solr for all search-like requests.
      # See also SolrHelper#solr_search_params.
      config.default_solr_params = {
        :qt => 'search',
        :rows => 10
      }

      # solr field configuration for search results/index views

      # solr fields that will be treated as facets by the blacklight application
      #   The ordering of the field names is the order of the display
      #
      # Setting a limit will trigger Blacklight's 'more' facet values link.
      # * If left unset, then all facet values returned by solr will be displayed.
      # * If set to an integer, then "f.somefield.facet.limit" will be added to
      # solr request, with actual solr request being +1 your configured limit --
      # you configure the number of items you actually want _displayed_ in a page.
      # * If set to 'true', then no additional parameters will be sent to solr,
      # but any 'sniffed' request limit parameters will be used for paging, with
      # paging at requested limit -1. Can sniff from facet.limit or
      # f.specific_field.facet.limit solr request params. This 'true' config
      # can be used if you set limits in :default_solr_params, or as defaults
      # on the solr side in the request handler itself. Request handler defaults
      # sniffing requires solr requests to be made with "echoParams=all", for
      # app code to actually have it echo'd back to see it.
      #
      # :show may be set to false if you don't want the facet to be drawn in the
      # facet bar

      config.add_facet_field 'sourceResource_type_name',
                             label: 'Type (pref)',
                             limit: 20
      config.add_facet_field 'sourceResource_type_providedLabel',
                             label: 'Type (provided)',
                             limit: 20
      config.add_facet_field 'sourceResource_format',
                             label: 'Format',
                             limit: 20
      config.add_facet_field 'sourceResource_language_name',
                             label: 'Language (pref)',
                             limit: 20
      config.add_facet_field 'sourceResource_language_providedLabel',
                             label: 'Language (provided)',
                             limit: 20
      config.add_facet_field 'sourceResource_spatial_name',
                             label: 'Place (pref)',
                             limit: 20
      config.add_facet_field 'sourceResource_spatial_providedLabel',
                             label: 'Place (provided)',
                             limit: 20
      config.add_facet_field 'sourceResource_subject_name',
                             label: 'Subject (pref)',
                             limit: 20
      config.add_facet_field 'sourceResource_subject_providedLabel',
                             label: 'Subject (provided)',
                             limit: 20
      config.add_facet_field 'sourceResource_collection_title',
                             label: 'Collection',
                             limit: 20
      config.add_facet_field 'dataProvider_name',
                             label: 'Data Provider (pref)',
                             limit: 20
      config.add_facet_field 'dataProvider_providedLabel',
                             label: 'Data Provider (provided)',
                             limit: 20
      config.add_facet_field 'sourceResource_creator_name',
                             label: 'Creator (pref)',
                             limit: 20
      config.add_facet_field 'sourceResource_creator_providedLabel',
                             label: 'Creator (provided)',
                             limit: 20

      # Have BL send all facet field names to Solr, which has been the default
      # previously. Simply remove these lines if you'd rather use Solr request
      # handler defaults, or have no facets.
      config.add_facet_fields_to_solr_request!

      # solr fields to be displayed in the index (search results) view.
      #   The ordering of the field names is the order of the display.
      # @note the :separator key is replaced by :separator_option in
      #   Blacklight v6.0.0. :separator_option is used with Rails #to_sentence.
      #   see https://github.com/projectblacklight/blacklight/wiki/Configuration---Results-View#fields
      config.add_index_field 'sourceResource_title', 
                             label: 'Title',
                             separator: '; '
      config.add_index_field 'sourceResource_creator_providedLabel', 
                             label: 'Creator',
                             separator: '; '
      config.add_index_field 'sourceResource_date_providedLabel', 
                             label: 'Date',
                             separator: '; '
      config.add_index_field 'sourceResource_description', 
                             label: 'Description',
                             separator: '; '
      config.add_index_field 'sourceResource_type_name', 
                             label: 'Type',
                             separator: '; '
      config.add_index_field 'sourceResource_format', 
                             label: 'Format',
                             separator: '; '
      config.add_index_field 'sourceResource_subject_providedLabel',
                             label: 'Subject',
                             separator: '; '
      config.add_index_field 'sourceResource_rights', 
                             label: 'Rights',
                             separator: '; '
      config.add_index_field 'sourceResource_collection_title',
                             label: 'Collection',
                             separator: '; '
      config.add_index_field 'dataProvider_providedLabel', 
                             label: 'Data Provider',
                             separator: '; '

      config.index.thumbnail_field = :preview_id

      config.show.route = { controller: 'records' }

      config.solr_document_model = Krikri::SearchIndexDocument

      config.view.gallery.partials = []
    end

    private

    ##
    # Construct a valid item URI from a local name, and use it to fetch a single
    # document from the search index.
    # Override method in Blacklight::SolrHelper.
    # TODO: This method is depreciated in Blacklight v5.10.
    # TODO: Write appropriate test for this functionality after it is updated
    # with Blacklight v5.10.
    # @param String id is a local name.
    def get_solr_response_for_doc_id(id=nil, extra_controller_params={})
      id = (RDF::URI(Krikri::Settings.marmotta.item_container) / id).to_s if id
      solr_response = solr_repository.find(id, extra_controller_params)
      [solr_response, solr_response.documents.first]
    end

    ##
    # Limit the records returned by a Solr request to those belonging to the
    # current provider.
    # @param [Hash] solr_parameters a hash of parameters to be sent to Solr.
    # @param [Hash] user_parameters a hash of user-supplied parameters.
    def records_by_provider(solr_params, user_params)
      if @provider_id.present?
        rdf_subject = Krikri::Provider.base_uri + @provider_id
        solr_params[:fq] ||= []
        solr_params[:fq] << "provider_id:\"#{rdf_subject}\""
      end
    end

    ##
    # Sets the provider id for use as a search filter/view
    def set_provider
      @provider_id = params[:provider]
    end
  end
end
