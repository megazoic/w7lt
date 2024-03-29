require_relative '../config/sequel'

module MemberTracker
  class UnitType < Sequel::Model
    one_to_many :units, :class=>"MemberTracker::Unit", key: :unit_type_id
    many_to_one :auth_users, :class=> "MemberTracker::Auth_user", key: :a_user_id
  end
  def UnitType.getID(name)
    uts = DB.from(:unit_types).select(:id, :type).all
    u_id = ''
    uts.each do |ut|
      if ut[:type] == name
        u_id = ut[:id]
      end
    end
    u_id
  end
end