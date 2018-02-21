require_relative '../../../app/member'
require_relative '../../../config/sequel'

module MemberTracker
  RSpec.describe Member, :aggregate_failures, :db do
    let(:member) {Member.new}
    let(:member_data) do
      {
        'fname' => 'joe',
        'lname' => 'smith'
      }
    end
    describe '#record' do
      context 'with a valid member' do
        it 'successfully saves a member in the DB' do
          result = member.record(member_data)
        
          expect(result).to be_success
          expect(DB[:members].all).to match [a_hash_including(
            id: result.member_id,
            fname: 'joe',
            lname: 'smith'
            )]
        end
      end
      context 'when the member_data lacks a lname' do
        it 'rejects the member as invalid' do
          member_data.delete('lname')
          result = member.record(member_data)
          expect(result).not_to be_success
          expect(result.member_id).to eq(nil)
          expect(result.error_message).to include('\'lname\' is required')
          expect(DB[:members].count).to eq(0)
        end
      end
    end
  end
end