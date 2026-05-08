class Api::V1::EventsController < ApplicationController
  def antel_arena
    render json: AntelArenaService.fetch_events
  end

  def billboard
    render json: CarteleraService.fetch_billboard
  end

  def billboard_event
    event_type = params[:event_type]

    return render json: { error: 'Invalid event type' }, status: :not_found unless CarteleraService.valid_type?(event_type)

    render json: CarteleraService.fetch_by_type(event_type)
  end
end
