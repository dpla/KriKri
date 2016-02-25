module Krikri::Harvesters
  ##
  # A harvester implementation for REST APIs. The default ApiHarvester expects
  # Solr-like JSON responses/records.
  #
  # An internal interface is provided for easier subclassing. A new API
  # harvester may reimplement:
  #   - #get_docs (to retrieve record docs from a response)
  #   - #get_count (to determine total record count from a response)
  #   - #get_identifier (to retrieve an indentifier from a record document)
  #   - #get_content (to retrieve a content string from a record document)
  #   - #next_options` (to generate the parameters for the next request)
  #
  # If the content type of the records is other than JSON, you will also want
  # to override `#content_type`.
  class CdlApiHarvester
    include Krikri::Harvester

    attr_reader :opts

    ##
    # @param opts [Hash] options for the harvester
    # @see .expected_opts
    def initialize(opts = {})
      super
      @opts = opts.fetch(:api, {})
    end

    ##
    # @return [Hash] A hash documenting the allowable options to pass to
    #   initializers.
    #
    # @see Krikri::Harvester::expected_opts
    def self.expected_opts
      {
        key: :api,
        opts: {
          params: { type: :string, required: false }
        }
      }
    end

    ##
    # @see Krikri::Harvester#count
    def count
      get_count(request(opts))
    end

    ##
    # @return [Enumerator::Lazy] an enumerator of the records targeted by this
    #   harvester.
    def records
      enumerate_records.lazy.map { |rec| build_record(rec) }
    end

    ##
    # Gets a single record with the given identifier from the API
    #
    # @return [Enumerator::Lazy] an enumerator over the ids for the records
    #   targeted by this harvester.
    def record_ids
      enumerate_records.lazy.map { |r| get_identifier(r) }
    end

    ##
    # @param identifier [#to_s] the identifier of the record to get
    # @return [#to_s] the record
    def get_record(identifier)
      response = request(:params => { :q => "id:#{identifier.to_s}" })
      build_record(get_docs(response).first)
    end

    ##
    # @return [String] the content type for the records generated by this
    #   harvester
    def content_type
      'application/json'
    end

    private

    ##
    # @param doc [#to_s] a raw record document with an identifier
    #
    # @return [String] the provider's identifier for the document
    def get_identifier(doc)
      doc['id']
    end

    ##
    # @param response [#to_s] a response from the REST API
    #
    # @return [Integer] a count of the total records found by the request
    def get_count(response)
      response['response']['numFound']
    end

    ##
    # @param response [#to_s] a response from the REST API
    #
    # @return [Array] an array of record documents from the response
    def get_docs(response)
      response['response']['docs']
    end

    ##
    # @param doc [#to_s] a raw record document
    #
    # @return [String] the record content
    def get_content(doc)
      doc.to_json
    end

    ##
    # Send a request via `RestClient`, and parse the result as JSON
    def request(request_opts)
      binding.pry
      JSON.parse(RestClient::Request.execute(method: :get, url: uri ,timeout: 10, request_opts))
    end

    ##
    # Given a current set of options and a number of records from the last
    # request, generate the options for the next request.
    #
    # @param opts [Hash] an options hash from the previous request
    # @param record_count [#to_i]
    #
    # @return [Hash] the next request's options hash
    def next_options(opts, record_count)
      old_start = opts['headers']['params'].fetch('start', 0)
      opts['headers']['params']['start'] = old_start.to_i + record_count
      opts
    end

    ##
    # @return [Enumerator] an enumerator over the records
    def enumerate_records
      Enumerator.new do |yielder|
        request_opts = opts.deep_dup
        loop do
          break if request_opts.nil?
          docs = get_docs(request(request_opts.dup))
          
          break if docs.empty?

          docs.each { |r| yielder << r }

          request_opts = next_options(request_opts, docs.count)
        end
      end
    end

    ##
    # Builds an instance of `@record_class` with the given doc's JSON as
    # content.
    #
    # @param doc [#to_json] the content to serialize as JSON in `#content`
    # @return [#to_s] an instance of @record_class with a minted id and
    #   content the given content
    def build_record(doc)
      @record_class.build(mint_id(get_identifier(doc)),
                          get_content(doc),
                          content_type)
    end
  end
end
