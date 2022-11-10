require_relative '../config/sequel'
module MemberTracker
  class AuditLog < Sequel::Model
    many_to_one :auth_user, :class=>Auth_user, key: :a_user_id
    many_to_one :payment, :class=>Payment, key: :pay_id
    many_to_one :member, :class=>Member, key: :mbr_id
    many_to_one :unit, :class=>Unit, key: :unit_id
    #keep 'active' last since it is associated with units table not members
    #note: "dropped_unit" is not included here but is used in payment rollback bc it tracks
    #changes to members_units join table when a family member leaves a unit by paying alone
    COLS_TO_TRACK = ["mbrship_renewal_date", "mbrship_renewal_halt", "mbrship_renewal_active",
      "mbrship_renewal_contacts", "mbr_type", "fam_unit_active"]
  end
end
