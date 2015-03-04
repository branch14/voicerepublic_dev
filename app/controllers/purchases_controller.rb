class PurchasesController < ApplicationController

  # step 1: setup purchase and redirect to paypal
  def express
    @purchase = Purchase.new quantity: params[:quantity],
                             ip: request.remote_ip
    redirect_to @purchase.setup.redirect_url
  end

  # step 2: display confirmation page
  def new
    @purchase = Purchase.new quantity: params[:quantity],
                             express_token: params[:token],
                             express_payer_id: params[:PayerID]
  end

  # step 3: process purchase
  def create
    @purchase = Purchase.new(purchase_params)
    @purchase.ip = request.remote_ip
    @purchase.owner = current_user

    if @purchase.save
      if @purchase.process
        render action: 'success'
      else
        render action: 'failure'
      end
    else
      render action: 'new' # TODO
    end
  end

  private

  def purchase_params
    params.require(:purchase).permit(:quantity,
                                     :express_token,
                                     :express_payer_id)
  end

end
