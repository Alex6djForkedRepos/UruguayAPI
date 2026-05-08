class Api::V1::EventsController < ApplicationController
  def antel_arena
    render json: AntelArenaService.fetch_events
  end

  def billboard
    render json: CarteleraService.fetch_billboard
  end

  def tickantel
    render json: TickantelService.fetch_events(**date_params)
  rescue ArgumentError
    render json: { error: 'Invalid date format. Use DD-MM-YYYY' }, status: :unprocessable_entity
  end

  def redtickets
    args = date_params.merge(details: params[:details] == 'true')
    render json: RedticketsService.fetch_events(**args)
  rescue ArgumentError
    render json: { error: 'Invalid date format. Use DD-MM-YYYY' }, status: :unprocessable_entity
  end

  def teatro_solis
    render json: TeatroSolisService.fetch_events(**date_params)
  rescue ArgumentError
    render json: { error: 'Invalid date format. Use DD-MM-YYYY' }, status: :unprocessable_entity
  end

  private

  VALID_PERIODS = %w[daily weekly monthly].freeze

  def date_params
    if params[:date]
      { date: Date.strptime(params[:date], '%d-%m-%Y') }
    elsif params[:period] && VALID_PERIODS.include?(params[:period])
      { period: params[:period] }
    else
      {}
    end
  end

  public

  def billboard_event
    event_type = params[:event_type]

    return render json: { error: 'Invalid event type' }, status: :not_found unless CarteleraService.valid_type?(event_type)

    render json: CarteleraService.fetch_by_type(event_type)
  end
end
