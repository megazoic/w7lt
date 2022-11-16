require_relative '../config/sequel'
module MemberTracker
  class Payment < Sequel::Model
    many_to_one :log, :class=>Log, key: :log_id
    many_to_one :auth_user, :class=>Auth_user, key: :a_user_id
    many_to_one :member, :class=>Member, key: :mbr_id
    one_to_many :auditLog, :class=>"MemberTracker::AuditLog", key: :pay_id
    many_to_one :paymentType, :class=>"MemberTracker::PaymentType", key: :payment_type_id
    many_to_one :paymentMethod, :class=>"MemberTracker::PaymentMethod", key: :payment_method_id
    @fees = {"none" => 0, "full" => 20, "family" => 25, "student" => 10, "honorary" => 0}
    class << self
      attr_reader :fees
    end
    def Payment.findLatestDues(mbr_id, name)
      latest_dp = nil
      if !Member[mbr_id].payments.nil?
        Member[mbr_id].payments.each do |p|
          if p.payment_type_id = PaymentTypeId.getID(name)
            if p.ts > latest_dp
              latest_dp = p.ts
            end
          end
        end
      end
      if latest_dp.nil
        return "no dues payment of type #{name} was found for mbr #{mbr_id}"
      else
        return ts
      end
    end
  end
end