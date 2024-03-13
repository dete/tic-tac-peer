access (all) contract TicTacPeer {

    // An enumeration to keep track of the current state of the contextual state machine
    access(all) enum State : Int8 {
        access(all) case Start
        access(all) case NeedSeed
        access(all) case CoinFlip
        access(all) case MoveX
        access(all) case Move0
        access(all) case Cleanup
    }

    access(all) struct ChannelStep {
        access(all) let state : State
        access(all) let signer : UInt32
        access(all) let context : AnyStruct

        init() {
            self.state = State.Start
            self.signer = 0x0
            self.context = 0
        }
    }

    // A tagging interface to indicate which structs are valid Events for
    // state transitions
    access(all) struct interface Event {}

    access(all) struct interface EventHandler {
        access(all) fun handleEvent(_ e: AnyStruct{Event}) : ChannelStep
    }

    access(all) struct StateTransition {
        access(all) let handler: AnyStruct{EventHandler}
        access(all) let newSignerRoles: [String]
        access(all) let newStates: [State]

        init(handler: AnyStruct{EventHandler}, newSignerRoles: [String], newStates: [State]) {
            self.handler = handler
            self.newSignerRoles = newSignerRoles
            self.newStates = newStates
        }
    }

    access(self) let stateTable : {State: {Type: AnyStruct{EventHandler}}}
    
    init() {
        self.stateTable = {
            State.Start: {
                Type<CommitSeed>(): CommitSeedHandler(),
                Type<Resign>(): ResignationHandler()
            }
        }
    }

    // An event used to indicate that the user wants to withdraw from the game
    // ALSO used to remove a user that times out from inactivity. If the user
    // "resigns" because of a time-out, the `timedOut()` method will return true.
    // NOTE: Most code should ignore the timedOut() value and treat a timeout and
    // manual resignation as identical.
    access(all) struct Resign : Event {
        access(contract) var _timedOut: Bool

        access(all) fun timedOut(): Bool {
            return self._timedOut
        }

        init() {
            self._timedOut = false
        }
    }

    // Allows a 
    access(all) struct CommitSeed : Event {
        access(all) let randomSeedCommitment: UInt256

        init(commitment: UInt256) {
            self.randomSeedCommitment = commitment
        }
    }

    access(all) struct CommitSeedHandler : EventHandler {
        access(all) fun handleEvent(_ e: AnyStruct{Event}): ChannelStep {
            return ChannelStep()
        }
    }

    access(all) struct ResignationHandler : EventHandler {
        access(all) fun handleEvent(_ e: AnyStruct{Event}): ChannelStep {
            return ChannelStep()
        }
    }

    access (all) struct GameState {
        access(all) let board: [UInt8]

        init(board: [UInt8]) {
            self.board = board
        }
    }


}