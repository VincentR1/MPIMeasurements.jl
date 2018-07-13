using Graphics: @mustimplement

export moveAbs, moveAbsUnsafe, moveRelUnsafe, movePark, moveCenter
export Robot, isReferenced, prepareRobot, getDefaultVelocity, setVelocity

# The following methods need to be implemented by a robot
@mustimplement moveAbs(robot::Robot, posX::typeof(1.0u"mm"),
  posY::typeof(1.0u"mm"), posZ::typeof(1.0u"mm"))
@mustimplement moveRel(robot::Robot, distX::typeof(1.0u"mm"),
    distY::typeof(1.0u"mm"), distZ::typeof(1.0u"mm"))
@mustimplement movePark(robot::Robot)
@mustimplement moveCenter(robot::Robot)
@mustimplement setBrake(robot::Robot,brake::Bool)
@mustimplement prepareRobot(robot::Robot)
@mustimplement isReferenced(robot::Robot)
@mustimplement getDefaultVelocity(robot::Robot)
@mustimplement setVelocity(robot::Robot,vel::Array{Int64,1})

""" `moveAbs(robot::Robot, setup::RobotSetup, xyzPos::Vector{typeof(1.0u"mm")})` """
function moveAbs(robot::Robot, setup::RobotSetup, xyzPos::Vector{typeof(1.0u"mm")})
  if length(xyzPos)!=3
    error("position vector xyzPos needs to have length = 3, but has length: ",length(xyzPos))
  end
  coordsTable = checkCoords(setup, xyzPos)
  moveAbsUnsafe(robot,xyzPos)
end

""" `moveAbsUnsafe(robot::Robot, xyzPos::Vector{typeof(1.0u"mm")})` """
function moveAbsUnsafe(robot::Robot, xyzPos::Vector{typeof(1.0u"mm")})
    if length(xyzPos)!=3
      error("position vector xyzPos needs to have length = 3, but has length: ",length(xyzPos))
    end
    moveAbs(robot,xyzPos[1],xyzPos[2],xyzPos[3])
end

# """ `moveRel(robot::Robot, setup::RobotSetup, xyzDist::Vector{typeof(1.0u"mm")})` """
# function moveRel(robot::Robot, setup::RobotSetup, xyzDist::Vector{typeof(1.0u"mm")})
#   if length(xyzDist)!=3
#     error("position vector xyzPos needs to have length = 3, but has length: ",length(xyzDist))
#   end
#   coordsTable = checkCoords(setup, xyzDist)
#   moveRelUnsafe(robot,xyzDist)
# end

""" `moveRelUnsafe(robot::Robot, xyzDist::Vector{typeof(1.0u"mm")})` """
function moveRelUnsafe(robot::Robot, xyzDist::Vector{typeof(1.0u"mm")})
    if length(xyzDist)!=3
      error("position vector xyzPos needs to have length = 3, but has length: ",length(xyzDist))
    end
    moveRel(robot,xyzDist[1],xyzDist[2],xyzDist[3])
end

function userGuidedPreparation(robot::Robot)
  display("IselRobot is NOT referenced and needs to be referenced!")
  display("Remove all attached devices from the robot before the robot will be referenced and move around!")
  display("Type \"REF\" in console to continue")
  userInput=readline(STDIN)
  if userInput=="REF"
      display("Are you sure you have removed everything and the robot can move freely without damaging anything? Type \"yes\" if you want to continue")
      uIYes = readline(STDIN)
      if uIYes == "yes"
          prepareRobot(robot)
          display("The robot is now referenced. You can mount your sample. Press any key to proceed.")
          userInput=readline(STDIN)
          return
      else
          error("User failed to type \"yes\" to continue")
      end
  else
      error("User failed to type \"REF\" to continue")
  end
end

if is_unix() && VERSION >= v"0.6"
  include("IselRobot.jl")
end

include("BrukerRobot.jl")
include("DummyRobot.jl")

function Robot(params::Dict)
  if params["type"] == "Dummy"
    return DummyRobot()
  elseif params["type"] == "Isel"
    return IselRobot(params)
  elseif params["type"] == "Bruker"
    return BrukerRobot(params["connection"])
  else
    error("Cannot create Robot!")
  end
end

include("Tour.jl")
