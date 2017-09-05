using Unitful

export IselRobot
export initZYX, refZYX, initRefZYX, simRefZYX
export moveRel, moveAbs, movePark, moveCenter
export getPos
export setZeroPoint, setBrake, setFree, setStartStopFreq, setAcceleration
export iselErrorCodes

const minVel = 30
const maxVel = 40000
const minAcceleration = 1
const maxAcceleration = 4000
const minstartStopFreq = 20
const maxstartStopFreq = 4000
const stepsPerTurn = 5000
const gearSlope = 5 # 1 turn equals 5mm feed
const stepsPermm =stepsPerTurn / gearSlope
const defaultVelocity = [1000,1000,1000]
const parkPos = [0.0,0.0,0.0]u"mm"
const centerPos = [0.0,0.0,0.0]u"mm"
const defCenterPos = [0,0,0]



"""Errorcodes Isel Robot """
const iselErrorCodes = Dict(
"0"=>"HandShake",
"1"=>"Error in Number, forbidden Character",
"2"=>"Endschalterfehler, NEU Initialisieren, Neu Referenzieren",
"3"=>"unzulässige Achsenzahl",
"4"=>"keine Achse definiert",
"5"=>"Syntax Fehler",
"6"=>"Speicherende",
"7"=>"unzulässige Parameterzahl",
"8"=>"zu speichernder Befehl inkorrekt",
"9"=>"Anlagenfehler",
"D"=>"unzulässige Geschwindigkeit",
"F"=>"Benutzerstop",
"G"=>"ungültiges Datenfeld",
"H"=>"Haubenbefehl",
"R"=>"Referenzfehler",
"A"=>"von dieser Steuerung nicht benutzt",
"B"=>"von dieser Steuerung nicht benutzt",
"C"=>"von dieser Steuerung nicht benutzt",
"E"=>"von dieser Steuerung nicht benutzt",
"="=>"von dieser Steuerung nicht benutzt"
)


"""
`iselRobot(portAdress::AbstractString)` e.g. `iselRobot("/dev/ttyS0")`

Initialize Isel Robot on port `portAdress`. For an overview
over the mid/high level API call `methodswith(SerialDevice{IselRobot})`.
"""
struct IselRobot <: AbstractRobot
  sd::SerialDevice
end

function queryIsel(sd::SerialDevice,cmd::String)
  flush(sd.sp)
  send(sd,string(cmd,sd.delim_write))
  i,c = LibSerialPort.sp_blocking_read(sd.sp.ref, 1, sd.timeout_ms)
  if i!=1
    error("Isel Robot did not respond!")
  end
  out = String( c )
  flush(sd.sp)
  return out
end


function IselRobot(portAdress::AbstractString)
  pause_ms::Int = 400
  timeout_ms::Int = 20000
  delim_read::String = "\r"
  delim_write::String = "\r"
  baudrate::Integer = 19200
  ndatabits::Integer= 8
  parity::SPParity = SP_PARITY_NONE
  nstopbits::Integer = 1

  try
    sp = SerialPort(portAdress)
    open(sp)
    set_speed(sp, baudrate)
    IselRobot( SerialDevice(sp,pause_ms,timeout_ms,delim_read,delim_write) )
  catch ex
    println("Connection fail: ",ex)
  end
end

""" Initializes all axes in order Z,Y,X """
function initZYX(robot::IselRobot)
  ret = queryIsel(robot.sd, "@07")
  checkError(ret)
end

""" References all axes in order Z,Y,X """
function refZYX(robot::IselRobot)
  ret = queryIsel(robot.sd, "@0R7")
  checkError(ret)
end

""" Initializes and references all axes in order Z,Y,X """
function initRefZYX(robot::IselRobot)
  initZYX(robot)
  refZYX(robot)
end

""" Move Isel Robot to center"""
function moveCenter(robot::IselRobot)
  moveAbs(robot, centerPos)
end

""" Move Isel Robot to park"""
function movePark(robot::IselRobot)
  moveAbs(robot, parkPos);
end

function _moveRel(robot::IselRobot,stepsX,velX,stepsY,velY,stepsZ,velZ)
  # for z-axis two steps and velocities are needed compare documentation
  # set second z steps to zero
  cmd=string("@0A"," ",stepsX,",",velX,
    ",",stepsY,",",velY,
    ",",stepsZ,",",velZ,
    ",",0,",",30)
  ret = queryIsel(robot.sd, cmd)
  checkError(ret)
end

""" Moves relative in mm `moveRel(sd::SerialDevice{IselRobot},distX::typeof(1.0u"mm"), velX,
  distY::typeof(1.0u"mm"), velY,   distZ::typeof(1.0u"mm"), velZ)` """
function moveRel(robot::IselRobot,distX::typeof(1.0u"mm"), velX,
  distY::typeof(1.0u"mm"), velY,   distZ::typeof(1.0u"mm"), velZ)
  _moveRel(robot,mm2Steps(distX),velX,mm2Steps(distY),velY,mm2Steps(distZ),velZ)
end

""" Moves relative in mm `moveRel(sd::SerialDevice{IselRobot},distX::typeof(1.0u"mm"),
  distY::typeof(1.0u"mm"), distZ::typeof(1.0u"mm"))` using const defaultVelocity """
function moveRel(robot::IselRobot,distX::typeof(1.0u"mm"),
  distY::typeof(1.0u"mm"), distZ::typeof(1.0u"mm"))
  moveRel(robot, distX, defaultVelocity[1],distY, defaultVelocity[2], distZ, defaultVelocity[3])
end

function mm2Steps(dist::typeof(1.0u"mm"))
    return round(Int64,ustrip(dist)*stepsPermm)
end

function steps2mm(steps)
  dist = steps/stepsPermm
  return dist*u"mm"
end

function _getPos(robot::IselRobot)
  ret = queryIsel(robot.sd, "@0P")
  checkError(ret)
  return ret
end

""" Returns Pos in mm """
function getPos(robot::IselRobot)
  ret = queryIsel(robot.sd, "@0P")
  checkError(ret)
  return parsePos(ret)
end

function parsePos(ret::AbstractString)
# 18 hex values, 6 digits per Axis order XYZ
  return ret
end

""" Simulates Reference Z,Y,X """
function simRefZYX(robot::IselRobot)
  ret = queryIsel(robot.sd, "@0N7")
  checkError(ret)
end

""" Sets the zero position for absolute moving at current axes position Z,Y,X """
function setZeroPoint(robot::IselRobot)
  ret = queryIsel(robot.sd, "@0n7")
  checkError(ret)
end

function _moveAbs(robot::IselRobot,stepsX,velX,stepsY,velY,stepsZ,velZ)
  # for z-axis two steps and velocities are needed compare documentation
  # set second z steps to zero
  cmd=string("@0M"," ",stepsX,",",velX,",",stepsY,",",velY,",",stepsZ,",",velZ,",",0,",",30)
  ret = queryIsel(robot.sd, cmd)
  checkError(ret)
end

""" Moves absolute in mm `moveRel(sd::SerialDevice{IselRobot},distX::typeof(1.0u"mm"), velX,
  distY::typeof(1.0u"mm"), velY,   distZ::typeof(1.0u"mm"), velZ)` """
function moveAbs(robot::IselRobot,posX::typeof(1.0u"mm"), velX, posY::typeof(1.0u"mm"), velY, posZ::typeof(1.0u"mm"), velZ)
  _moveAbs(robot,mm2Steps(posX),velX,mm2Steps(posY),velY,mm2Steps(posZ),velZ)
end

""" Moves absolute in mm `moveRel(sd::SerialDevice{IselRobot},distX::typeof(1.0u"mm"), velX,
  distY::typeof(1.0u"mm"), velY,   distZ::typeof(1.0u"mm"), velZ)` """
function moveAbs(sd::IselRobot,posX::typeof(1.0u"mm"), posY::typeof(1.0u"mm"), posZ::typeof(1.0u"mm"))
  _moveAbs(robot,posX,defaultVelocity[1],posY,defaultVelocity[2],posZ,defaultVelocity[3])
end

""" Sets Acceleration """
function setAcceleration(robot::IselRobot,acceleration)
  ret = queryIsel(robot.sd, string("@0J",acceleration))
  checkError(ret)
end

""" Sets StartStopFrequency"""
function setStartStopFreq(robot::IselRobot,frequency)
  ret = querry(robot.sd,string("@0j",frequency))
  checkError(ret)
end

""" Sets brake, brake=false no current on brake , brake=true current on brake """
function setBrake(robot::IselRobot, brake::Bool)
  flag = brake ? 1 : 0
  ret = queryIsel(robot.sd, string("@0g",flag))
  checkError(ret)
end

""" Sets free, Freifahren axis, wenn Achse über den Referenzpunkt gefahren ist"""
function setFree(robot::IselRobot, axis)
  ret = queryIsel(robot.sd,  string("@0F",axis))
  checkError(ret)
end

""" `prepareRobot(sd::SerialDevice{IselRobot})` """
function prepareRobot(robot::IselRobot)
  # check sensor for reference
  initRefZYX(robot)
  moveAbs(robot, defCenterPos[1],defaultVelocity[1],defCenterPos[2],defaultVelocity[2],defCenterPos[3],defaultVelocity[3])
  setZeroPoint(robot)
end

function checkError(ret::AbstractString)
  if ret != "0"
    error("Command failed: ",iselErrorCodes[ret])
  end
  return nothing
end
