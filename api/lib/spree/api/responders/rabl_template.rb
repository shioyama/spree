module Spree
  module Api
    module Responders
      module RablTemplate
        def to_format
          if template
            render template, :status => options[:status] || 200
          else
            super
          end

        rescue ActionView::MissingTemplate => e
          api_behavior(e)
        end

        def template
          options[:default_template]
        end
      end
    end
  end
end
