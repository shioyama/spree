module Spree
  class ShipmentMailer < BaseMailer
    def shipped_email(shipment, resend = false)
      @shipment = shipment.is_a?(Spree::Shipment) ? shipment : Spree::Shipment.find(shipment)
      subject = (resend ? "[#{t(:resend).upcase}] " : '')
      subject += "#{Spree::Config[:site_name]} #{t('shipment_mailer.shipped_email.subject')} ##{@shipment.order.number}"
      mail(to: @shipment.order.email, from: from_address, subject: subject)
    end
  end
end
