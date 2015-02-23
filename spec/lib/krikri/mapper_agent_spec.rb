describe Krikri::Mapper::Agent do
  opts = { name: :agent_map, generator_uri: 'http://example.org/agent/gen/1' }
  it_behaves_like 'a software agent', opts

  subject { described_class.new(opts) }

  let(:generator_uri) { 'http://example.org/agent/gen/1' }
  let(:activity_uri) { 'http://example.org/agent/act/1' }
  let(:mapping_name) { :agent_map }
  let(:opts) { { name: mapping_name, generator_uri: generator_uri } }

  describe '::queue_name' do
    it { expect(described_class.queue_name.to_s).to eq 'mapping' }
  end

  describe '#run' do
    let(:record_double) { instance_double(DPLA::MAP::Aggregation) }
    let(:records) do
      [record_double, record_double.clone, record_double.clone]
    end

    before do
      allow(subject).to receive(:records).and_return([:record1, :record2])
      allow(record_double).to receive(:node?).and_return(true)
      allow(record_double).to receive(:mint_id!)
      allow(record_double).to receive(:save)
    end

    context 'with errors thrown' do
      before do
        allow(record_double).to receive(:node?).and_raise(StandardError.new)
        allow(record_double).to receive(:rdf_subject).and_return('123')
        allow(Krikri::Mapper).to receive(:map).and_return(records)
      end

      it 'logs errors' do
        expect(Rails.logger).to receive(:error)
                                 .with(start_with('Error saving record: 123'))
                                 .exactly(3).times
        subject.run(activity_uri)
      end
    end

    context 'with mapped records returned' do
      before do
        expect(Krikri::Mapper).to receive(:map)
                                   .with(mapping_name, subject.records)
                                   .and_return(records)
      end

      it 'calls mapper' do
        subject.run
      end

      it 'sets generator' do
        records.each do |rec|
          statement = double
          allow(RDF).to receive(:Statement)
                         .with(rec, RDF::PROV.wasGeneratedBy, activity_uri)
                         .and_return(statement)
          expect(rec).to receive(:<<).with(statement)
        end
        subject.run(activity_uri)
      end
    end
  end

  # TODO: these tests are tied closely to implementation.
  #       This is a code smell. Consider refactor of ProvenanceQueryClient
  #       and #records.
  describe '#records' do
    include_context 'provenance queries'

    let(:record_double) { instance_double(Krikri::OriginalRecord) }

    it 'returns a lazy enum' do
      expect(subject.records).to be_a Enumerator::Lazy
    end

    it 'gets records for generated by harvest_activity' do
      expect(Krikri::ProvenanceQueryClient).to receive(:find_by_activity)
        .with(generator_uri).and_return(query)
      expect(Krikri::OriginalRecord).to receive(:load).with(uri.to_s)
        .and_return(record_double)

      expect(subject.records).to contain_exactly(record_double)
    end
  end
end
