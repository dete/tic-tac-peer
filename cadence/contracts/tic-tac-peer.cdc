import StateChannel from "StateChannel"

access (all) contract TicTacPeer {

    access(all) struct TicTacToeContext: StateChannel.ComparableAppContext {
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

        access(all) view fun matchesContext(_ otherContext: {StateChannel.ComparableAppContext}): Bool {
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

    access(self) let stateTable : {StateChannel.State: {Type: StateChannel.StateTransition}}
    
    init() {
        self.stateTable = {
            StateChannel.State.Start: {
                Type<CommitSeed>(): StateChannel.StateTransition(
                    handler: CommitSeedHandler(),
                    newSignerRoles: ["!initiator"],
                    newStates: [StateChannel.State.NeedSeed]),
                Type<StateChannel.Resign>(): StateChannel.StateTransition(
                    handler: ResignationHandler(),
                    newSignerRoles: ["!signer"],
                    newStates: [StateChannel.State.Cleanup])
            },
            StateChannel.State.NeedSeed: {
                Type<ProvideSeed>(): StateChannel.StateTransition(
                    handler: ProvideSeedHandler(),
                    newSignerRoles: ["initiator"],
                    newStates: [StateChannel.State.MoveX]),
                Type<StateChannel.Resign>(): StateChannel.StateTransition(
                    handler: ResignationHandler(),
                    newSignerRoles: ["!signer"],
                    newStates: [StateChannel.State.Cleanup])
            },
            StateChannel.State.CoinFlip: {
                Type<RevealSeed>(): StateChannel.StateTransition(
                    handler: RevealSeedHandler(),
                    newSignerRoles: ["player"],
                    newStates: [StateChannel.State.MoveX]),
                Type<StateChannel.Resign>(): StateChannel.StateTransition(
                    handler: ResignationHandler(),
                    newSignerRoles: ["!signer"],
                    newStates: [StateChannel.State.Cleanup])
            },
            StateChannel.State.MoveX: {
                Type<RevealSeed>(): StateChannel.StateTransition(
                    handler: MoveHandler(),
                    newSignerRoles: ["player", "!signer"],
                    newStates: [StateChannel.State.MoveO]),
                Type<StateChannel.Resign>(): StateChannel.StateTransition(
                    handler: ResignationHandler(),
                    newSignerRoles: ["!signer"],
                    newStates: [StateChannel.State.Cleanup])
            },
            StateChannel.State.MoveO: {
                Type<RevealSeed>(): StateChannel.StateTransition(
                    handler: MoveHandler(),
                    newSignerRoles: ["player", "!signer"],
                    newStates: [StateChannel.State.MoveX]),
                Type<StateChannel.Resign>(): StateChannel.StateTransition(
                    handler: ResignationHandler(),
                    newSignerRoles: ["!signer"],
                    newStates: [StateChannel.State.Cleanup])
            }
        }
    }

    access(all) struct ResignationHandler : StateChannel.ActionHandler {
        access(all) fun handleAction(context: StateChannel.ChannelContext, action: {StateChannel.Action}) : StateChannel.ChannelContext {
            let otherParticipantList = context.participants.values.filter(
                view fun (_ p: StateChannel.Participant):Bool {
                    return !p.hasRole("signer")
                }
            ) 

            return context.removeSigner().updateSigner(id:otherParticipantList[0].id).updateState(StateChannel.State.Cleanup)
        }
    }

    access(all) struct CloseChannel: StateChannel.Action {
    }

    access(all) struct CloseHandler: StateChannel.ActionHandler {
        access(all) fun handleAction(context: StateChannel.ChannelContext, action: {StateChannel.Action}) : StateChannel.ChannelContext {
            pre {
                context.participants.length == 1: "Can only close the channel when one participant is left"
            }

            return context.removeSigner()
        }
    }

    access(all) struct CommitSeed : StateChannel.Action {
        access(all) let commitment: UInt256

        init(commitment: UInt256) {
            self.commitment = commitment
        }
    }

    access(all) struct CommitSeedHandler : StateChannel.ActionHandler {
        access(all) fun handleAction(context: StateChannel.ChannelContext, action: {StateChannel.Action}) : StateChannel.ChannelContext {
            var appContext: TicTacPeer.TicTacToeContext = context.appContext as! TicTacToeContext
            let commitAction: TicTacPeer.CommitSeed = action as! CommitSeed

            appContext = appContext.addP1SeedCommitment(p1SeedCommitment: commitAction.commitment)

            return context.updateState(StateChannel.State.NeedSeed).updateSigner(id:1).updateAppContext(appContext)
        }
    }

    access(all) struct ProvideSeed : StateChannel.Action {
        access(all) let contribution: UInt256

        init(contribution: UInt256) {
            self.contribution = contribution
        }
    }

    access(all) struct ProvideSeedHandler : StateChannel.ActionHandler {
        access(all) fun handleAction(context: StateChannel.ChannelContext, action: {StateChannel.Action}) : StateChannel.ChannelContext {
            var appContext: TicTacPeer.TicTacToeContext = context.appContext as! TicTacToeContext
            let provideAction: TicTacPeer.ProvideSeed = action as! ProvideSeed

            appContext = appContext.addP2SeedContribution(p2SeedContribution: provideAction.contribution)

            return context.updateState(StateChannel.State.CoinFlip).updateSigner(id:0).updateAppContext(appContext)
        }
    }

    access(all) struct RevealSeed: StateChannel.Action {
        access(all) let seed: UInt256
        access(all) let salt: UInt256

        init(seed: UInt256, salt: UInt256) {
            self.seed = seed
            self.salt = salt
        }
    }

    access(all) struct RevealSeedHandler: StateChannel.ActionHandler {
        access(all) fun handleAction(context: StateChannel.ChannelContext, action: {StateChannel.Action}) : StateChannel.ChannelContext {
            var appContext = context.appContext as! TicTacToeContext
            let revealAction = action as! RevealSeed

            var hashedData = revealAction.seed.toBigEndianBytes()
            hashedData.concat(revealAction.salt.toBigEndianBytes())

            let correctCommitment = UInt256.fromBigEndianBytes(HashAlgorithm.SHA3_256.hash(hashedData))!

            assert(appContext.p1SeedCommitment == correctCommitment, message: "Revealed seed doesn't match commitment")

            let channelSeed = revealAction.seed ^ appContext.p2SeedContribution

            let startingPlayer = UInt32(channelSeed % 2)

            let playerList = context.participants.values.filter(
                view fun (_ p: StateChannel.Participant):Bool {
                    return p.hasRole("player")
                }
            )

            let startingPlayerId = playerList[startingPlayer].id

            return context.updateState(StateChannel.State.MoveX).updateSigner(id:startingPlayerId)
        }
    }

    access(all) struct Move: StateChannel.Action {
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

    access(all) struct MoveHandler: StateChannel.ActionHandler {
        access(all) fun handleAction(context: StateChannel.ChannelContext, action: {StateChannel.Action}) : StateChannel.ChannelContext {
            var appContext = context.appContext as! TicTacToeContext
            let moveAction = action as! Move

            assert(appContext.boardContents(cellX: moveAction.x, cellY: moveAction.y) == 0, message: "Attempt to play in an occupied cell")

            let playerSymbol: UInt8 = (context.state == StateChannel.State.MoveX) ? 1 : 2
            appContext = appContext.modifyBoard(cellX: moveAction.x, cellY: moveAction.y, newValue: playerSymbol)

            let otherPlayerList = context.participants.values.filter(
                view fun (_ p: StateChannel.Participant):Bool {
                    return p.hasRole("player") && !p.hasRole("signer")
                }
            )

            return context.updateAppContext(appContext).updateSigner(id:otherPlayerList[0].id)
        }
    }
}