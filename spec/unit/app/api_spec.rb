require_relative '../../../app/api'
require 'rack/test'

module MemberTracker
  
  RSpec.describe API do
    include Rack::Test::Methods
    
    def app
      API.new(addrbook: addrbook)
    end
    let(:addrbook) {instance_double ('MemberTracker::Addrbook')}
    describe 'POST /members' do
      context 'when the member is successfully recorded' do
        let(:member) {{'some'=>'data'}}
        before do
          allow(addrbook).to receive(:record)
          .with(member)
          .and_return(RecordResult.new(true, 417, nil))
        end
          
        it 'returns the member id' do
          post '/members', JSON.generate(member)
          parsed = JSON.parse(last_response.body)
          expect(parsed).to include('member_id' => 417)
        end
        it 'responds with a 200 (OK)' do
          post '/members', JSON.generate(member)
          expect(last_response.status).to eq(200)
        end
      end

      # ... next context will go here...

      context 'when the member fails validation' do
        let(:member) {{'some'=>'data'}}
        before do
          allow(addrbook).to receive(:record)
          .with(member)
          .and_return(RecordResult.new(false, 417, 'member incomplete'))
        end
        it 'returns an error message' do
          post '/members', JSON.generate(member)
          parsed = JSON.parse(last_response.body)
          expect(parsed).to include('error' => 'member incomplete')
        end
        it 'responds with a 422 (Unprocessable entity)' do
          post '/members', JSON.generate(member)
          expect(last_response.status).to eq(422)
        end
      end
    end
  end
end