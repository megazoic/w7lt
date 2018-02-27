require_relative '../../../app/member'


module MemberTracker
  #:aggregate_failures allows muclitple failures to be recorded p87
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
    describe '#members_with_lastname' do
      it 'returns all members with a name provided' do
        result_1 = member.record(member_data.merge('fname' => 'fred',
        'lname' => 'smith'))
        result_2 = member.record(member_data.merge('fname' => 'mary',
        'lname' => 'smith'))
        result_3 = member.record(member_data.merge('fname' => 'fred',
        'lname' => 'jones'))
        member.members_with_lastname('smith').each {|m|
          expect(m.lname).to eq('smith')
        }
      end
      it 'returns a blank array when there are no matching members' do
        expect(member.members_with_lastname('smith')).to eq([])
      end
    end
  end
end