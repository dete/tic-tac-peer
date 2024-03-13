access (all) contract TicTacPeer {


    access(all) struct Participant {
        access(all) let signingKey: PublicKey
        access(all) let roles: [String]

        init(signingKey: PublicKey, roles: [String]) {
            self.signingKey = signingKey
            self.roles = roles
        }

        access(all) fun hasRole(role: String): Bool {
            return self.roles.contains(role)
        }

        access(contract) fun removeRole(role: String): Participant {
            if let roleIndex: Int = self.roles.firstIndex(of: role) {
                var modifiedRoles: [String] = self.roles
                modifiedRoles.remove(at: roleIndex)

                return Participant(signingKey: self.signingKey, roles: modifiedRoles)
            }
            else {
                return self
            }
        }

        access(contract) fun addRole(role: String): Participant {
            if self.roles.contains(role) {
                return self
            }
            else {
                var modifiedRoles: [String] = self.roles
                modifiedRoles.append(role)

                return Participant(signingKey: self.signingKey, roles: modifiedRoles)

            }
        }
    }

    access(all) struct interface AppContext {
        access(all) fun isValid(): Bool
    }

    access(all) struct interface ComparableAppContext: AppContext {
        access(all) fun matchesContext(_ otherContext: AnyStruct): Bool {
            pre {
                self.getType() == otherContext.getType()
            }
        }
    }

    access(all) struct ChannelContext {
        access(all) let state : State
        access(all) let signerIndex : Int?
        access(all) let participants: [Participant]
        access(all) let appContext : {AppContext}

        init(state: State, signerIndex: Int?, participants: [Participant], appContext: {AppContext}) {
            self.state = state
            self.signerIndex = signerIndex
            self.participants = participants
            self.appContext = appContext
        }

        access(all) fun matchesChannelContextWithoutAppContext(_ otherContext: ChannelContext): Bool {
            if self.state != otherContext.state { return false }
            if self.signerIndex != otherContext.signerIndex { return false }
            // TODO: Participants

            return true
        }

        access(all) fun matchesChannelContext(_ otherContext: ChannelContext): Bool {
            pre {
                self.appContext.isInstance(Type<{ComparableAppContext}>()): "Matching channel contexts requires comparable app contexts."
                otherContext.appContext.isInstance(Type<{ComparableAppContext}>()): "Matching channel contexts requires comparable app contexts."
            }
            if !self.matchesChannelContextWithoutAppContext(otherContext) { return false }

            if self.appContext.getType() != otherContext.appContext.getType() { return false }

            let comparableSelf: {TicTacPeer.ComparableAppContext}  = self.appContext as! {ComparableAppContext}
            let comparableOther: {TicTacPeer.ComparableAppContext} = self.appContext as! {ComparableAppContext}

            return comparableSelf.matchesContext(comparableOther)
        }

        access(all) fun updateState(_ newState: State): ChannelContext {
            return ChannelContext(state: newState, signerIndex: self.signerIndex, participants: self.participants, appContext: self.appContext)
        }

        access(all) fun updateSignerIndex(_ newSignerIndex: Int): ChannelContext {
            pre {
                newSignerIndex < self.participants.length: "Invalid signer index"
            }
            return ChannelContext(state: self.state, signerIndex: newSignerIndex, participants: self.participants, appContext: self.appContext)
        }

        access(all) fun removeParticipant(_ removedIndex: Int): ChannelContext {
            pre {
                removedIndex < self.participants.length: "Invalid participant index"
            }
            var newParticipantList: [TicTacPeer.Participant] = self.participants
            newParticipantList.remove(at: removedIndex)
            var newSignerIndex: Int? = self.signerIndex

            if self.signerIndex != nil {
                if self.signerIndex! == removedIndex || newParticipantList.length == 0 {
                    newSignerIndex = nil
                }
                else if self.signerIndex! < newSignerIndex! {
                    newSignerIndex = newSignerIndex! - 1
                }
            }

            return ChannelContext(state: self.state, signerIndex: newSignerIndex, participants: newParticipantList, appContext: self.appContext)
        }

        access(all) fun updateAppContext(_ newAppContext: {AppContext}): ChannelContext {
            return ChannelContext(state: self.state, signerIndex: self.signerIndex, participants: self.participants, appContext: newAppContext)
        }

        access(all) fun isValid(): Bool {
            if self.participants.length != 0 && self.signerIndex == nil { return false }
            if self.signerIndex != nil && self.signerIndex! >= self.participants.length { return false }


            return true
        }
    }

    // An enumeration to keep track of the current state of the contextual state machine
    access(all) enum State : Int8 {
        access(all) case Start
        access(all) case NeedSeed
        access(all) case CoinFlip
        access(all) case MoveX
        access(all) case MoveO
        access(all) case Cleanup
    }

    access(all) struct TicTacToeContext: ComparableAppContext {
        access(all) let p1SeedCommitment: UInt256
        access(all) let p2SeedContribution: UInt256
        access(all) let board: [UInt8; 9]

        init(p1SeedCommitment: UInt256, p2SeedContribution: UInt256, board: [UInt8; 9]) {
            self.p1SeedCommitment = p1SeedCommitment
            self.p2SeedContribution = p2SeedContribution
            self.board = board
        }

        access(all) fun addP1SeedCommitment(p1SeedCommitment: UInt256): TicTacToeContext {
            pre {
                self.p1SeedCommitment == 0: "Seed commitment already set"
            }
            return TicTacToeContext(p1SeedCommitment: p1SeedCommitment, p2SeedContribution: self.p2SeedContribution, board: self.board)
        }

        access(all) fun addP2SeedContribution(p2SeedContribution: UInt256): TicTacToeContext {
            pre {
                self.p1SeedCommitment != 0: "Missing seed commitment"
                self.p2SeedContribution == 0: "Seed contribution already set"
            }
            return TicTacToeContext(p1SeedCommitment: self.p1SeedCommitment, p2SeedContribution: p2SeedContribution, board: self.board)
        }

        access(all) fun modifyBoard(cellX: UInt8, cellY: UInt8, newValue: UInt8): TicTacToeContext {
            pre {
                cellX < 3 && cellY < 6: "Invalid coordinate"
                newValue == 1 || newValue == 2 : "Invalid square contents"
                self.board[cellY*3 + cellX] == 0 : "Square occupied"
            }
            var newBoard = self.board
            self.board[cellY*3 + cellX] = newValue

            return TicTacToeContext(p1SeedCommitment: self.p1SeedCommitment, p2SeedContribution: self.p2SeedContribution, board: newBoard)
        }

        access(all) fun isValid(): Bool {
            if self.p1SeedCommitment == 0 && self.p2SeedContribution != 0 { return false }

            for cellValue in self.board {
                if cellValue > 2 { return false }
            }

            return true
        }

        access(all) fun matchesContext(_ otherContext: {ComparableAppContext}): Bool {
            let other: TicTacPeer.TicTacToeContext = otherContext as! TicTacToeContext

            if self.p1SeedCommitment != other.p1SeedCommitment { return false }
            if self.p2SeedContribution != other.p2SeedContribution { return false }
            if self.board != other.board { return false }

            return true
        }
    }

    access(self) fun emptyContext(): TicTacToeContext {
        return TicTacToeContext(p1SeedCommitment: 0, p2SeedContribution: 0, board: [0, 0, 0, 0, 0, 0, 0, 0, 0])
    }

    // A tagging interface to indicate which structs are valid actionss for
    // state transitions
    access(all) struct interface Action {}

    access(all) struct interface ActionHandler {
        access(all) fun handleAction(oldStep: ChannelContext, action: {Action}) : ChannelContext
        access(all) fun isValidTransition(oldStep: ChannelContext, action: {Action}, newStep: ChannelContext): Bool
    }

    access(all) struct StateTransition {
        access(all) let handler: {ActionHandler}
        access(all) let newSignerRoles: [String]
        access(all) let newStates: [State]

        init(handler: {ActionHandler}, newSignerRoles: [String], newStates: [State]) {
            self.handler = handler
            self.newSignerRoles = newSignerRoles
            self.newStates = newStates
        }
    }

    access(self) let stateTable : {State: {Type: StateTransition}}
    
    init() {
        self.stateTable = {
            State.Start: {
                Type<CommitSeed>(): StateTransition(
                    handler: CommitSeedHandler(),
                    newSignerRoles: ["!initiator"],
                    newStates: [State.NeedSeed]),
                Type<Resign>(): StateTransition(
                    handler: ResignationHandler(),
                    newSignerRoles: ["!signer"],
                    newStates: [State.Cleanup])
            },
            State.NeedSeed: {
                Type<ProvideSeed>(): StateTransition(
                    handler: ProvideSeedHandler(),
                    newSignerRoles: ["player"],
                    newStates: [State.MoveX]),
                Type<Resign>(): StateTransition(
                    handler: ResignationHandler(),
                    newSignerRoles: ["!signer"],
                    newStates: [State.Cleanup])
            }
        }
    }

    // An action used to indicate that the user wants to withdraw from the game
    // ALSO used to remove a user that times out from inactivity. If the user
    // "resigns" because of a time-out, the `timedOut()` method will return true.
    // NOTE: Most code should ignore the timedOut() value and treat a timeout and
    // manual resignation as identical.
    access(all) struct Resign : Action {
        access(contract) var _timedOut: Bool

        access(all) fun timedOut(): Bool {
            return self._timedOut
        }

        init() {
            self._timedOut = false
        }
    }

    // Allows a 
    access(all) struct CommitSeed : Action {
        access(all) let commitment: UInt256

        init(commitment: UInt256) {
            self.commitment = commitment
        }
    }

    access(all) struct CommitSeedHandler : ActionHandler {
        access(all) fun handleAction(context: ChannelContext, action: {Action}) : ChannelContext {
            var appContext: TicTacPeer.TicTacToeContext = context.appContext as! TicTacToeContext
            let commitAction: TicTacPeer.CommitSeed = action as! CommitSeed

            appContext = appContext.addP1SeedCommitment(p1SeedCommitment: commitAction.commitment)

            return context.updateState(State.NeedSeed).updateSignerIndex(1).updateAppContext(appContext)
        }
 
        access(all) fun isValidTransition(context: ChannelContext, action: {Action}, newContext: ChannelContext): Bool {
            let expectedContext: ChannelContext = self.handleAction(context: context, action: action)

            return expectedContext.matchesChannelContext(newContext)
        }
   }

    access(all) struct ProvideSeed : Action {
        access(all) let contribution: UInt256

        init(contribution: UInt256) {
            self.contribution = contribution
        }
    }

    access(all) struct ProvideSeedHandler : ActionHandler {
        access(all) fun handleAction(context: ChannelContext, action: Action) : ChannelContext {
            var appContext: TicTacPeer.TicTacToeContext = context.appContext as! TicTacToeContext
            let provideAction: TicTacPeer.ProvideSeed = action as! ProvideSeed

            appContext = appContext.addP2SeedContribution(p2SeedContribution: provideAction.contribution)

            return context.updateState(State.CoinFlip).updateSignerIndex(0).updateAppContext(appContext)
        }
 
        access(all) fun isValidTransition(context: ChannelContext, action: Action, newContext: ChannelContext): Bool {
            let expectedContext: ChannelContext = self.handleAction(context: context, action: action)

            return expectedContext.matchesChannelContext(newContext)
        }
    }

    access(all) struct ResignationHandler : ActionHandler {
        access(all) fun handleAction(oldStep: ChannelContext, action: Action) : ChannelContext {
            return oldStep.removeParticipant(oldStep.signerIndex!).updateSignerIndex(0).updateState(State.Cleanup)
        }
    }

    access (all) struct GameState {
        access(all) let board: [UInt8]

        init(board: [UInt8]) {
            self.board = board
        }
    }


}