require_relative '../../../app/api'

module MemberTracker
  RSpec.describe PaymentService, :db do
    let(:dues_type_id)     { DB[:payment_types].where(type: 'Dues').get(:id) }
    let(:donation_type_id) { DB[:payment_types].where(type: 'Donation Other').get(:id) }
    let(:cash_method_id)   { DB[:payment_methods].where(mode: 'Cash').get(:id) }
    let(:auth_uid)         { 22 }

    def donation_params(member, overrides = {})
      { "mbr_id" => member.id.to_s, "payment_type" => donation_type_id.to_s,
        "payment_method" => cash_method_id.to_s, "nonDues_pmt" => "25", "notes" => ""
      }.merge(overrides)
    end

    def dues_params(member, overrides = {})
      { "mbr_id" => member.id.to_s, "payment_type" => dues_type_id.to_s,
        "payment_method" => cash_method_id.to_s, "mbr_type" => "full",
        "mbr_type_old" => "none", "notes" => ""
      }.merge(overrides)
    end

    describe '.call' do
      context 'donation payment' do
        it 'returns an ok result pointing to the payments page' do
          member = create_member
          result = PaymentService.call(donation_params(member), auth_uid)
          expect(result.ok?).to be true
          expect(result.redirect_path).to eq('/m/payments/show')
        end

        it 'creates exactly one payment record and one donation log record' do
          member = create_member
          donation_action_id = DB[:actions].where(type: 'donation').get(:id)
          PaymentService.call(donation_params(member), auth_uid)
          expect(DB[:payments].where(mbr_id: member.id).count).to eq(1)
          expect(DB[:logs].where(mbr_id: member.id, action_id: donation_action_id).count).to eq(1)
        end

        it 'links the payment to its log' do
          member = create_member
          PaymentService.call(donation_params(member), auth_uid)
          pay = DB[:payments].where(mbr_id: member.id).first
          log = DB[:logs].where(id: pay[:log_id]).first
          expect(log).not_to be_nil
          expect(log[:mbr_id]).to eq(member.id)
        end

        it 'returns an error result when the amount is blank (DB constraint)' do
          member = create_member
          result = PaymentService.call(donation_params(member, "nonDues_pmt" => ""), auth_uid)
          expect(result.ok?).to be false
          expect(result.redirect_path).to eq('/m/payments/show')
        end
      end

      context 'dues payment — new member (no prior renewal date)' do
        it 'returns an ok result' do
          member = create_member
          result = PaymentService.call(dues_params(member), auth_uid)
          expect(result.ok?).to be true
        end

        it 'sets mbr_type and mbrship_renewal_date on the member' do
          member = create_member
          PaymentService.call(dues_params(member), auth_uid)
          updated = Member[member.id]
          expect(updated.mbr_type).to eq('full')
          expect(updated.mbrship_renewal_date).not_to be_nil
        end

        it 'writes an audit log entry for the mbr_type change' do
          member = create_member
          PaymentService.call(dues_params(member), auth_uid)
          expect(DB[:audit_logs].where(mbr_id: member.id, column: 'mbr_type').count).to eq(1)
        end
      end

      context 'dues payment — returning member (existing renewal date)' do
        it 'advances the renewal date and returns an ok result' do
          old_date = DateTime.now - 400
          member = create_member(mbr_type: 'full', mbrship_renewal_date: old_date)
          result = PaymentService.call(dues_params(member, "mbr_type_old" => "full"), auth_uid)
          expect(result.ok?).to be true
          new_date = Member[member.id].mbrship_renewal_date
          expect(new_date.to_time).to be > old_date.to_time
        end
      end

      context 'family dues payment — no family unit exists' do
        it 'returns an error result without creating a payment record' do
          member = create_member
          params = dues_params(member, "mbr_type" => "family", "mbr_type_old" => "none")
          result = PaymentService.call(params, auth_uid)
          expect(result.ok?).to be false
          expect(result.redirect_path).to eq('/m/unit/create')
          expect(result.message).to include('family unit')
          expect(DB[:payments].where(mbr_id: member.id).count).to eq(0)
        end
      end

      context 'non-renewal followup auto-completion on dues payment' do
        it 'marks an open non_renew_followup action as completed' do
          member = create_member
          action = create_member_action(member: member)
          expect(action.completed).to be false

          PaymentService.call(dues_params(member), auth_uid)

          expect(DB[:member_actions].where(id: action.id).get(:completed)).to be true
        end

        it 'creates a log entry linked to the closed action' do
          member = create_member
          action = create_member_action(member: member)
          PaymentService.call(dues_params(member), auth_uid)
          log = DB[:logs].where(mbr_action_id: action.id).first
          expect(log).not_to be_nil
          expect(log[:notes]).to include('dues payment')
        end

        it 'closes multiple open followup actions for the same member' do
          member  = create_member
          action1 = create_member_action(member: member)
          action2 = create_member_action(member: member)
          PaymentService.call(dues_params(member), auth_uid)
          expect(DB[:member_actions].where(id: action1.id).get(:completed)).to be true
          expect(DB[:member_actions].where(id: action2.id).get(:completed)).to be true
        end

        it 'does not affect followup actions belonging to a different member' do
          payer   = create_member
          other   = create_member
          action  = create_member_action(member: other)
          PaymentService.call(dues_params(payer), auth_uid)
          expect(DB[:member_actions].where(id: action.id).get(:completed)).to be false
        end

        it 'does not close followup actions when the payment is a donation' do
          member = create_member
          action = create_member_action(member: member)
          PaymentService.call(donation_params(member), auth_uid)
          expect(DB[:member_actions].where(id: action.id).get(:completed)).to be false
        end
      end

      context 'callme note in jotform submission' do
        it 'creates a member_action when notes contain "leader? Yes"' do
          member = create_member
          params = donation_params(member, "notes" => "form data\nAre you a club leader? Yes, please call")
          PaymentService.call(params, auth_uid)
          expect(DB[:member_actions].where(member_target: member.id).count).to eq(1)
        end

        it 'does not create a member_action when notes lack the leader callback trigger' do
          member = create_member
          PaymentService.call(donation_params(member), auth_uid)
          expect(DB[:member_actions].where(member_target: member.id).count).to eq(0)
        end
      end
    end
  end
end
