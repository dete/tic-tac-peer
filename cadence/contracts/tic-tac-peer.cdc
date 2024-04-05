access (all) contract TicTacPeer {

    access(all) struct Participant {
        access(all) let signingKey: PublicKey
        access(all) let id: Int32
        access(all) let roles: {String: Bool}

        view init(signingKey: PublicKey, id: Int32, roles: {String: Bool}) {
            self.signingKey = signingKey
            self.id = id
            self.roles = roles
        }

        access(all) view fun hasRole(_ role: String): Bool {
            return self.roles.containsKey(role)
        }

        access(contract) fun removeRole(_ role: String): Participant {
            if self.hasRole(role) {
                var modifiedRoles = self.roles
                modifiedRoles.remove(key: role)

                return Participant(signingKey: self.signingKey, id: self.id, roles: modifiedRoles)
            }
            else {
                return self
            }
        }

        access(contract) view fun addRole(_ role: String): Participant {
            if self.hasRole(role) {
                return self
            }
            else {
                var modifiedRoles = self.roles
                modifiedRoles[role] = true

                return Participant(signingKey: self.signingKey, id: self.id, roles: modifiedRoles)

            }
        }
    }

    access(all) struct interface AppContext {
        access(all) view fun isValid(): Bool
    }

    access(all) struct interface ComparableAppContext: AppContext {
        access(all) view fun matchesContext(_ otherContext: {ComparableAppContext}): Bool {
            pre {
                self.getType() == otherContext.getType()
            }
        }
    }

    access(all) struct ChannelContext {
        access(all) let state : State
        access(all) let signerId : Int32?
        access(all) let participants: {Int32: Participant}
        access(self) let nextParticipantId: Int32
        access(all) let appContext : {AppContext}

        view init(state: State, signerId: Int32?, participants: {Int32: Participant}, nextParticipantId: Int32, appContext: {AppContext}) {
            self.state = state
            self.signerId = signerId
            self.participants = participants
            self.nextParticipantId = nextParticipantId
            self.appContext = appContext
        }

        access(all) view fun matchesChannelContextWithoutAppContext(_ otherContext: ChannelContext): Bool {
            if self.state != otherContext.state { return false }
            if self.signerId != otherContext.signerId { return false }
            // TODO: Participants

            return true
        }

        access(all) view fun matchesChannelContext(_ otherContext: ChannelContext): Bool {
            pre {
                self.appContext.isInstance(Type<{ComparableAppContext}>()): "Matching channel contexts requires comparable app contexts."
                otherContext.appContext.isInstance(Type<{ComparableAppContext}>()): "Matching channel contexts requires comparable app contexts."
            }
            if !self.matchesChannelContextWithoutAppContext(otherContext) { return false }

            if self.appContext.getType() != otherContext.appContext.getType() { return false }

            let comparableSelf: {TicTacPeer.ComparableAppContext}  = self.appContext as! {ComparableAppContext}
            let comparableOther: {TicTacPeer.ComparableAppContext} = otherContext.appContext as! {ComparableAppContext}

            return comparableSelf.matchesContext(comparableOther)
        }

        access(all) view fun updateState(_ newState: State): ChannelContext {
            return ChannelContext(state: newState, signerId: self.signerId, participants: self.participants,
                    nextParticipantId: self.nextParticipantId, appContext: self.appContext)
        }

        access(all) view fun updateSigner(id newSignerId: Int32): ChannelContext {
            pre {
                self.participants.containsKey(newSignerId): "Invalid signer ID"
            }
            return ChannelContext(state: self.state, signerId: newSignerId, participants: self.participants,
                    nextParticipantId: self.nextParticipantId, appContext: self.appContext)
        }

        access(all) view fun addParticipant(_ newParticipant: Participant): ChannelContext {
            var newParticipantSet = self.participants
            newParticipantSet[self.nextParticipantId] = Participant(signingKey: newParticipant.signingKey, id: self.nextParticipantId, roles: newParticipant.roles)
            
            return ChannelContext(state: self.state, signerId: self.signerId, participants: newParticipantSet,
                    nextParticipantId: self.nextParticipantId + 1, appContext: self.appContext)
        }

        access(all) fun removeSigner(): ChannelContext {
            pre {
                self.signerId != nil: "No signer to remove"
                self.participants.containsKey(self.signerId!): "Signer ID invalid"
            }
            var newParticipantSet = self.participants
            newParticipantSet.remove(key: self.signerId!)

            return ChannelContext(state: self.state, signerId: nil, participants: newParticipantSet, 
                    nextParticipantId: self.nextParticipantId, appContext: self.appContext)
        }

        // TODO: Add convenience functions to add/remove roles

        access(all) view fun updateAppContext(_ newAppContext: {AppContext}): ChannelContext {
            return ChannelContext(state: self.state, signerId: self.signerId, participants: self.participants,
                    nextParticipantId: self.nextParticipantId, appContext: newAppContext)
        }

        access(all) view fun isValid(): Bool {
            if self.participants.length != 0 && self.signerId == nil { return false }

            return self.appContext.isValid()
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

        view init(p1SeedCommitment: UInt256, p2SeedContribution: UInt256, board: [UInt8; 9]) {
            self.p1SeedCommitment = p1SeedCommitment
            self.p2SeedContribution = p2SeedContribution
            self.board = board
        }

        access(all) view fun addP1SeedCommitment(p1SeedCommitment: UInt256): TicTacToeContext {
            pre {
                self.p1SeedCommitment == 0: "Seed commitment already set"
            }
            return TicTacToeContext(p1SeedCommitment: p1SeedCommitment, p2SeedContribution: self.p2SeedContribution, board: self.board)
        }

        access(all) view fun addP2SeedContribution(p2SeedContribution: UInt256): TicTacToeContext {
            pre {
                self.p1SeedCommitment != 0: "Missing seed commitment"
                self.p2SeedContribution == 0: "Seed contribution already set"
            }
            return TicTacToeContext(p1SeedCommitment: self.p1SeedCommitment, p2SeedContribution: p2SeedContribution, board: self.board)
        }

        access(all) view fun boardContents(cellX: UInt8, cellY: UInt8): UInt8 {
            return self.board[cellY*3 + cellX]
        }

        access(all) view fun modifyBoard(cellX: UInt8, cellY: UInt8, newValue: UInt8): TicTacToeContext {
            pre {
                cellX < 3 && cellY < 6: "Invalid coordinate"
                newValue == 1 || newValue == 2 : "Invalid square contents"
                self.board[cellY*3 + cellX] == 0 : "Square occupied"
            }
            var newBoard = self.board
            newBoard[cellY*3 + cellX] = newValue

            return TicTacToeContext(p1SeedCommitment: self.p1SeedCommitment, p2SeedContribution: self.p2SeedContribution, board: newBoard)
        }

        access(all) view fun isValid(): Bool {
            if self.p1SeedCommitment == 0 && self.p2SeedContribution != 0 { return false }

            for cellValue in self.board {
                if cellValue > 2 { return false }
            }

            return true
        }

        access(all) view fun matchesContext(_ otherContext: {ComparableAppContext}): Bool {
            let other: TicTacPeer.TicTacToeContext = otherContext as! TicTacToeContext

            if self.p1SeedCommitment != other.p1SeedCommitment { return false }
            if self.p2SeedContribution != other.p2SeedContribution { return false }
            if self.board != other.board { return false }

            return true
        }
    }

    access(self) view fun emptyContext(): TicTacToeContext {
        return TicTacToeContext(p1SeedCommitment: 0, p2SeedContribution: 0, board: [0, 0, 0, 0, 0, 0, 0, 0, 0])
    }

    // A tagging interface to indicate which structs are valid actionss for
    // state transitions
    access(all) struct interface Action {}

    access(all) struct interface ActionHandler {
        access(all) fun handleAction(context: ChannelContext, action: {Action}) : ChannelContext

        access(all) fun isValidTransition(context: ChannelContext, action: {Action}, newContext: ChannelContext): Bool {

            assert(context.appContext.isInstance(Type<{ComparableAppContext}>()), message: "Default validity check requires ComparableAppContext.")

            let expectedContext: ChannelContext = self.handleAction(context: context, action: action)

            return expectedContext.matchesChannelContext(newContext)
        }
    }

    access(all) struct StateTransition {
        access(all) let handler: {ActionHandler}
        access(all) let newSignerRoles: [String]
        access(all) let newStates: [State]

        view init(handler: {ActionHandler}, newSignerRoles: [String], newStates: [State]) {
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
                    newSignerRoles: ["initiator"],
                    newStates: [State.MoveX]),
                Type<Resign>(): StateTransition(
                    handler: ResignationHandler(),
                    newSignerRoles: ["!signer"],
                    newStates: [State.Cleanup])
            },
            State.CoinFlip: {
                Type<RevealSeed>(): StateTransition(
                    handler: RevealSeedHandler(),
                    newSignerRoles: ["player"],
                    newStates: [State.MoveX]),
                Type<Resign>(): StateTransition(
                    handler: ResignationHandler(),
                    newSignerRoles: ["!signer"],
                    newStates: [State.Cleanup])
            },
            State.MoveX: {
                Type<RevealSeed>(): StateTransition(
                    handler: MoveHandler(),
                    newSignerRoles: ["player", "!signer"],
                    newStates: [State.MoveO]),
                Type<Resign>(): StateTransition(
                    handler: ResignationHandler(),
                    newSignerRoles: ["!signer"],
                    newStates: [State.Cleanup])
            },
            State.MoveO: {
                Type<RevealSeed>(): StateTransition(
                    handler: MoveHandler(),
                    newSignerRoles: ["player", "!signer"],
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

        access(all) view fun timedOut(): Bool {
            return self._timedOut
        }

        init() {
            self._timedOut = false
        }
    }

    access(all) struct ResignationHandler : ActionHandler {
        access(all) fun handleAction(context: ChannelContext, action: {Action}) : ChannelContext {
            let otherParticipantList = context.participants.values.filter(view fun (_ p: Participant):Bool {
                return !p.hasRole("signer")
            })

            return context.removeSigner().updateSigner(id:otherParticipantList[0].id).updateState(State.Cleanup)
        }
    }

    access(all) struct CloseChannel: Action {
    }

    access(all) struct CloseHandler: ActionHandler {
        access(all) fun handleAction(context: ChannelContext, action: {Action}) : ChannelContext {
            pre {
                context.participants.length == 1: "Can only close the channel when one participant is left"
            }

            return context.removeSigner()
        }
    }

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

            return context.updateState(State.NeedSeed).updateSigner(id:1).updateAppContext(appContext)
        }
    }

    access(all) struct ProvideSeed : Action {
        access(all) let contribution: UInt256

        init(contribution: UInt256) {
            self.contribution = contribution
        }
    }

    access(all) struct ProvideSeedHandler : ActionHandler {
        access(all) fun handleAction(context: ChannelContext, action: {Action}) : ChannelContext {
            var appContext: TicTacPeer.TicTacToeContext = context.appContext as! TicTacToeContext
            let provideAction: TicTacPeer.ProvideSeed = action as! ProvideSeed

            appContext = appContext.addP2SeedContribution(p2SeedContribution: provideAction.contribution)

            return context.updateState(State.CoinFlip).updateSigner(id:0).updateAppContext(appContext)
        }
    }

    access(all) struct RevealSeed: Action {
        access(all) let seed: UInt256
        access(all) let salt: UInt256

        init(seed: UInt256, salt: UInt256) {
            self.seed = seed
            self.salt = salt
        }
    }

    access(all) struct RevealSeedHandler: ActionHandler {
        access(all) fun handleAction(context: ChannelContext, action: {Action}) : ChannelContext {
            var appContext = context.appContext as! TicTacToeContext
            let revealAction = action as! RevealSeed

            var hashedData = revealAction.seed.toBigEndianBytes()
            hashedData.concat(revealAction.salt.toBigEndianBytes())

            let correctCommitment = UInt256.fromBigEndianBytes(HashAlgorithm.SHA3_256.hash(hashedData))!

            assert(appContext.p1SeedCommitment == correctCommitment, message: "Revealed seed doesn't match commitment")

            let channelSeed = revealAction.seed ^ appContext.p2SeedContribution

            let startingPlayer = UInt32(channelSeed % 2)

            let playerList = context.participants.values.filter(view fun (_ p: Participant):Bool {
                return p.hasRole("player")
            })

            let startingPlayerId = playerList[startingPlayer].id

            return context.updateState(State.MoveX).updateSigner(id:startingPlayerId)
        }
    }

    access(all) struct Move: Action {
        access(all) let x: UInt8
        access(all) let y: UInt8

        init(x: UInt8, y: UInt8) {
            pre {
                x < 3: "Invalid move location"
                y < 3: "Invalid move location"
            }
            self.x = x
            self.y = y
        }
    }

    access(all) struct MoveHandler: ActionHandler {
        access(all) fun handleAction(context: ChannelContext, action: {Action}) : ChannelContext {
            var appContext = context.appContext as! TicTacToeContext
            let moveAction = action as! Move

            assert(appContext.boardContents(cellX: moveAction.x, cellY: moveAction.y) == 0, message: "Attempt to play in an occupied cell")

            let playerSymbol: UInt8 = (context.state == State.MoveX) ? 1 : 2
            appContext = appContext.modifyBoard(cellX: moveAction.x, cellY: moveAction.y, newValue: playerSymbol)

            let otherPlayerList = context.participants.values.filter(view fun (_ p: Participant):Bool {
                return p.hasRole("player") && !p.hasRole("signer")
            })

            return context.updateAppContext(appContext).updateSigner(id:otherPlayerList[0].id)
        }
    }
}