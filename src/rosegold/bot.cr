require "../rosegold"
require "./control/*"

class Rosegold::Bot
  private getter client : Client

  getter inventory : Inventory

  def initialize(@client)
    @inventory = Inventory.new client
    @interact = Interactions.new client
  end

  # Does not connect immediately.
  def new(address : String)
    new Client.new address
  end

  # Connects to the server and waits for being ingame.
  def self.join_game(address : String)
    new Client.new(address).tap &.join_game
  end

  delegate host, port, connect, connected?, online_players, on, to: client
  delegate uuid, username, feet, eyes, health, food, saturation, gamemode, to: client.player
  delegate main_hand, to: inventory
  delegate stop_using_hand, start_digging, stop_digging, to: @interact

  def disconnect_reason
    client.connection.try &.close_reason
  end

  # Revive the player if dead. Does nothing if alive.
  def respawn
    raise "Not implemented" # TODO send packet
  end

  # Send a message or slash command.
  def chat(message : String)
    client.queue_packet Serverbound::ChatMessage.new message
  end

  # Is adjusted to server TPS.
  def wait_ticks(ticks : Int32)
    sleep ticks / 20 # TODO adjust to server TPS, changing over time
  end

  def wait_tick
    wait_ticks 1
  end

  # Direction the player is looking.
  def look
    client.player.look
  end

  # Waits for the new look to be sent to the server.
  def look=(look : Look)
    client.physics.look = look
  end

  # Waits for the new look to be sent to the server.
  def look=(vec : Vec3d)
    client.physics.look = vec
  end

  # Computes the new look from the current look.
  # Waits for the new look to be sent to the server.
  def look(&block : Look -> Look)
    client.physics.look = block.call look
  end

  # Sets the yaw of the look
  # Waits for the new look to be sent to the server
  def yaw=(yaw : Float64)
    self.look = look.with_yaw yaw
  end

  # Sets the pitch of the look
  # Waits for the new look to be sent to the server
  def pitch=(pitch : Float64)
    self.look = look.with_pitch pitch
  end

  def yaw
    look.yaw
  end

  def pitch
    look.pitch
  end

  # Waits for the new look to be sent to the server.
  def look_at(location : Vec3d)
    client.physics.look = Look.from_vec location - eyes
  end

  # Waits for the new look to be sent to the server.
  def look_at_horizontal(location : Vec3d)
    look_at location.with_y eyes.y
  end

  # Moves straight towards `location`.
  # Waits for arrival.
  def move_to(location : Vec3d)
    client.physics.move location
  end

  # Moves straight towards `location`.
  # Waits for arrival.
  def move_to(x : Float64, z : Float64)
    client.physics.move Vec3d.new x, feet.y, z
  end

  # Computes the destination location from the current feet location.
  # Moves straight towards the destination.
  # Waits for arrival.
  def move_to(&block : Vec3d -> Vec3d)
    client.physics.move block.call feet
  end

  # Stop moving towards the target specified in #move_to
  # Dequeue any jump queued with #start_jump
  def stop_moving
    client.physics.move = nil
    client.physics.jump_queued = false
  end

  # Jumps the next time the player is on the ground.
  def start_jump
    client.physics.jump_queued = true
  end

  # Use #interact_block to enter a bed.
  def leave_bed
    client.queue_packet Serverbound::EntityAction.new \
      client.player.entity_id, :leave_bed
  end

  # The active (main hand) hotbar slot number (1-9).
  def hotbar_selection
    client.player.hotbar_selection + 1
  end

  # Selects the active (main hand) hotbar slot number (1-9).
  def hotbar_selection=(index : UInt8)
    # TODO check range
    client.queue_packet Serverbound::HeldItemChange.new index - 1
    client.player.hotbar_selection = index - 1
  end

  def swap_hands
    client.queue_packet Serverbound::PlayerDigging.new :swap_hands
  end

  def drop_hand_single
    client.queue_packet Serverbound::PlayerDigging.new :drop_hand_single
    client.queue_packet Serverbound::SwingArm.new
  end

  def drop_hand_full
    client.queue_packet Serverbound::PlayerDigging.new :drop_hand_full
    client.queue_packet Serverbound::SwingArm.new
  end

  # Moves the slot to the hotbar and selects it.
  # This is faster and less error-prone than moving slots around individually.
  def pick_slot(slot_nr : UInt16)
    client.queue_packet Serverbound::PickItem.new slot_nr
  end

  # Activates the "use" button.
  def start_using_hand(hand : Hand = :main_hand)
    # can't delegate this because it wouldn't pick up the symbol as a Hand value
    @interact.start_using_hand hand
  end

  # Looks in the direction of `target`, then
  # activates and immediately deactivates the `use` button.
  def use_hand(target : Vec3d? | Look? = nil, hand : Hand = :main_hand)
    look_at target if target.is_a? Vec3d
    look target if target.is_a? Look
    start_using_hand hand
    stop_using_hand
  end

  # Looks at that face of that block, then activates and immediately deactivates the `use` button.
  def place_block_against(block : Vec3i, face : BlockFace)
    use_hand block + face
  end

  # Looks at that target, then activates the `attack` button.
  def start_digging(target : Vec3d? | Look? = nil)
    look_at target if target.is_a? Vec3d
    look target if target.is_a? Look
    @interact.start_digging
  end

  # Looks in the direction of target, then
  # activates the `attack` button, waits `ticks`, and deactivates it again.
  def dig(ticks : Int32, target : Vec3d? | Look? = nil)
    start_digging target
    wait_ticks ticks
    stop_digging
  end

  # Looks in the direction of target, then
  # activates and immediately deactivates the `attack` button.
  def attack(target : Vec3d? | Look? = nil)
    dig 0, target
  end
end
