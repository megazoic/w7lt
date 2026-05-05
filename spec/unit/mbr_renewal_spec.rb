require_relative '../../app/api'

module MemberTracker
  RSpec.describe MbrRenewal, :db do
    let(:dues_type_id)  { DB[:payment_types].where(type: 'Dues').get(:id) }
    let(:cash_method_id) { DB[:payment_methods].where(mode: 'Cash').get(:id) }

    def family_unit_type_id
      DB[:unit_types].where(type: 'family').get(:id) ||
        DB[:unit_types].insert(type: 'family', a_user_id: 22, descr: 'family unit')
    end

    def create_family_unit(members:)
      ut_id = family_unit_type_id
      unit_id = DB[:units].insert(unit_type_id: ut_id, a_user_id: 22, active: 1, ts: Time.now)
      members.each { |m| DB[:members_units].insert(unit_id: unit_id, mbr_id: m.id) }
      unit_id
    end

    def insert_dues_payment(member, ts: Time.now)
      log_id = DB[:logs].insert(mbr_id: member.id, a_user_id: 22, ts: Time.now,
                                action_id: DB[:actions].where(type: 'mbr_renew').get(:id),
                                notes: 'test dues payment')
      DB[:payments].insert(mbr_id: member.id, a_user_id: 22,
                           payment_type_id: dues_type_id, payment_method_id: cash_method_id,
                           payment_amount: 30, ts: ts, log_id: log_id)
    end

    def member_hash(member)
      { fname: member.fname, lname: member.lname, callsign: member.callsign,
        email: member.email, mbr_type: member.mbr_type }
    end

    describe '.findAndPurgeFamily' do
      it 'returns an empty hash for an empty input' do
        expect(MbrRenewal.findAndPurgeFamily({})).to eq({})
      end

      it 'passes non-family members through unchanged' do
        member = create_member(mbr_type: 'full')
        input = { member.id => member_hash(member) }
        result = MbrRenewal.findAndPurgeFamily(input)
        expect(result).to eq(input)
      end

      it 'returns an error string for a family member with no units' do
        member = create_member(mbr_type: 'family')
        input = { member.id => member_hash(member) }
        result = MbrRenewal.findAndPurgeFamily(input)
        expect(result).to be_a(String)
        expect(result).to match(/error.*no unit found/)
      end

      it 'returns an error string for a family member whose unit has no dues payments' do
        payer   = create_member(mbr_type: 'family')
        partner = create_member(mbr_type: 'family')
        create_family_unit(members: [payer, partner])
        input = { payer.id => member_hash(payer) }
        result = MbrRenewal.findAndPurgeFamily(input)
        expect(result).to be_a(String)
        expect(result).to match(/error.*dues payments for unit/)
      end

      it 'returns the member with the most recent dues payment for a family unit' do
        payer   = create_member(mbr_type: 'family')
        partner = create_member(mbr_type: 'family')
        create_family_unit(members: [payer, partner])
        insert_dues_payment(payer, ts: Time.now - 10)
        insert_dues_payment(partner, ts: Time.now - 400)

        input = { payer.id => member_hash(payer), partner.id => member_hash(partner) }
        result = MbrRenewal.findAndPurgeFamily(input)

        expect(result).to be_a(Hash)
        expect(result.keys).to contain_exactly(payer.id)
      end

      it 'deduplicates when multiple family members of the same unit are in the input' do
        payer   = create_member(mbr_type: 'family')
        partner = create_member(mbr_type: 'family')
        create_family_unit(members: [payer, partner])
        insert_dues_payment(payer)

        # Both members are in the renewal hash but should collapse to one entry
        input = { payer.id => member_hash(payer), partner.id => member_hash(partner) }
        result = MbrRenewal.findAndPurgeFamily(input)
        expect(result.size).to eq(1)
        expect(result.keys.first).to eq(payer.id)
      end

      it 'handles a mix of family and non-family members' do
        full_mbr = create_member(mbr_type: 'full')
        payer    = create_member(mbr_type: 'family')
        partner  = create_member(mbr_type: 'family')
        create_family_unit(members: [payer, partner])
        insert_dues_payment(payer)

        input = {
          full_mbr.id => member_hash(full_mbr),
          payer.id    => member_hash(payer),
          partner.id  => member_hash(partner)
        }
        result = MbrRenewal.findAndPurgeFamily(input)
        expect(result.keys).to contain_exactly(full_mbr.id, payer.id)
      end
    end
  end
end
