require_relative '../../app/api'

module MemberTracker
  RSpec.describe Payment, :db do
    let(:dues_type_id)     { DB[:payment_types].where(type: 'Dues').get(:id) }
    let(:donation_type_id) { DB[:payment_types].where(type: 'Donation Other').get(:id) }
    let(:cash_method_id)   { DB[:payment_methods].where(mode: 'Cash').get(:id) }

    def insert_payment(member, type_id, ts: Time.now)
      log_id = DB[:logs].insert(mbr_id: member.id, a_user_id: 22, ts: Time.now,
                                action_id: DB[:actions].where(type: 'donation').get(:id),
                                notes: 'test')
      DB[:payments].insert(mbr_id: member.id, a_user_id: 22,
                           payment_type_id: type_id, payment_method_id: cash_method_id,
                           payment_amount: 25, ts: ts, log_id: log_id)
    end

    describe '.findLatestDues' do
      it 'returns nil when the member has no payments' do
        member = create_member
        expect(Payment.findLatestDues(member.id, 'Dues')).to be_nil
      end

      it 'returns nil when the member has only non-dues payments' do
        member = create_member
        insert_payment(member, donation_type_id)
        expect(Payment.findLatestDues(member.id, 'Dues')).to be_nil
      end

      it 'returns the timestamp of a single dues payment' do
        member = create_member
        ts = Time.now - 10
        insert_payment(member, dues_type_id, ts: ts)
        result = Payment.findLatestDues(member.id, 'Dues')
        expect(result).not_to be_nil
        expect(result.to_i).to eq(ts.to_i)
      end

      it 'returns the most recent dues timestamp when there are multiple' do
        member = create_member
        older = Time.now - 400
        newer = Time.now - 10
        insert_payment(member, dues_type_id, ts: older)
        insert_payment(member, dues_type_id, ts: newer)
        result = Payment.findLatestDues(member.id, 'Dues')
        expect(result.to_i).to eq(newer.to_i)
      end

      it 'ignores donation payments when finding the latest dues' do
        member = create_member
        dues_ts = Time.now - 200
        donation_ts = Time.now - 5
        insert_payment(member, dues_type_id, ts: dues_ts)
        insert_payment(member, donation_type_id, ts: donation_ts)
        result = Payment.findLatestDues(member.id, 'Dues')
        expect(result.to_i).to eq(dues_ts.to_i)
      end
    end
  end
end
