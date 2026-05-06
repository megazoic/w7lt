require_relative '../../app/api'

module MemberTracker
  RSpec.describe MemberAction, :db do
    let(:call_type_id) { DB[:member_action_types].where(name: 'call_member').get(:id) }

    def create_call_action(member, ts: Time.now, completed: false)
      id = DB[:member_actions].insert(
        member_target:         member.id,
        a_user_id:             22,
        member_action_type_id: call_type_id,
        completed:             completed,
        notes:                 'test call-me action',
        ts:                    ts
      )
      MemberAction[id]
    end

    describe '.expire_stale_call_actions' do
      it 'returns 0 and does nothing when there are no stale actions' do
        expect(MemberAction.expire_stale_call_actions(22)).to eq(0)
      end

      it 'does not expire a call_member action created recently' do
        member = create_member
        create_call_action(member, ts: Time.now - (30 * 24 * 3600))
        expect(MemberAction.expire_stale_call_actions(22)).to eq(0)
      end

      it 'expires a call_member action older than 4 months and returns 1' do
        member = create_member
        create_call_action(member, ts: DateTime.now << 5)
        expect(MemberAction.expire_stale_call_actions(22)).to eq(1)
      end

      it 'marks the stale action as completed in the database' do
        member = create_member
        action = create_call_action(member, ts: DateTime.now << 5)
        MemberAction.expire_stale_call_actions(22)
        expect(DB[:member_actions].where(id: action.id).get(:completed)).to be true
      end

      it 'creates a log entry linked to the expired action via mbr_action_id' do
        member = create_member
        action = create_call_action(member, ts: DateTime.now << 5)
        MemberAction.expire_stale_call_actions(22)
        log = DB[:logs].where(mbr_action_id: action.id).first
        expect(log).not_to be_nil
        expect(log[:notes]).to include('auto-completed')
      end

      it 'does not expire a non_renew_followup action even if stale' do
        member  = create_member
        nrf_id  = DB[:member_action_types].where(name: 'non_renew_followup').get(:id)
        DB[:member_actions].insert(
          member_target: member.id, a_user_id: 22,
          member_action_type_id: nrf_id, completed: false,
          notes: 'stale non-renewal', ts: DateTime.now << 5
        )
        expect(MemberAction.expire_stale_call_actions(22)).to eq(0)
      end

      it 'does not re-expire an already-completed stale action' do
        member = create_member
        create_call_action(member, ts: DateTime.now << 5, completed: true)
        expect(MemberAction.expire_stale_call_actions(22)).to eq(0)
      end

      it 'expires multiple stale actions and returns the correct count' do
        m1 = create_member
        m2 = create_member
        create_call_action(m1, ts: DateTime.now << 5)
        create_call_action(m2, ts: DateTime.now << 6)
        expect(MemberAction.expire_stale_call_actions(22)).to eq(2)
      end
    end
  end
end
