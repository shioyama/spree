module Spree
  module Api
    class ProductsController < Spree::Api::BaseController
      respond_to :json

      def index
        @products = product_scope.ransack(params[:q]).result.page(params[:page]).per(params[:per_page])
        respond_with(@products)
      end

      def show
        @product = find_product(params[:id])
        respond_with(@product)
      end

      def new
      end

      def create
        authorize! :create, Product
        params[:product][:available_on] ||= Time.now

        variants_attributes = params[:product].delete(:variants_attributes) || []
        option_type_attributes = params[:product].delete(:option_types) || []

        @product = Product.new(params[:product])
        begin
          if @product.save
            variants_attributes.each do |variant_attribute|
              variant = @product.variants.new
              variant.update_attributes(variant_attribute)
            end

            option_type_attributes.each do |name|
              option_type = OptionType.where(name: name).first_or_initialize do |option_type|
                option_type.presentation = name
                option_type.save!
              end

              @product.option_types << option_type unless @product.option_types.include?(option_type)
            end

            respond_with(@product, :status => 201, :default_template => :show)
          else
            invalid_resource!(@product)
          end
        rescue ActiveRecord::RecordNotUnique
          retry
        end
      end

      def update
        authorize! :update, Product

        variants_attributes = params[:product].delete(:variants_attributes) || []
        option_type_attributes = params[:product].delete(:option_types) || []

        @product = find_product(params[:id])
        if @product.update_attributes(params[:product])
          variants_attributes.each do |variant_attribute|
            # update the variant if the id is present in the payload
            if variant_attribute['id'].present?
              @product.variants.find(variant_attribute['id'].to_i).update_attributes(variant_attribute)
            else
              variant = @product.variants.new
              variant.update_attributes(variant_attribute)
            end
          end

          option_type_attributes.each do |name|
            option_type = OptionType.where(name: name).first_or_initialize do |option_type|
              option_type.presentation = name
              option_type.save!
            end

            @product.option_types << option_type unless @product.option_types.include?(option_type)
          end

          respond_with(@product, :status => 200, :default_template => :show)
        else
          invalid_resource!(@product)
        end
      end

      def destroy
        authorize! :delete, Product
        @product = find_product(params[:id])
        @product.update_attribute(:deleted_at, Time.now)
        @product.variants_including_master.update_all(:deleted_at => Time.now)
        respond_with(@product, :status => 204)
      end
    end
  end
end
