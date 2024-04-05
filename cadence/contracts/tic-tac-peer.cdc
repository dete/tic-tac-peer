import StateChannels from "StateChannels"

access (all) contract TicTacPeer {

    access(all) struct TicTacToeContext: StateChannels.ComparableAppContext {
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

        access(all) view fun matchesContext(_ otherContext: {StateChannels.ComparableAppContext}): Bool {
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

    access(self) let stateTable : {StateChannels.State: {Type: StateChannels.StateTransition}}
    
    init() {
        self.stateTable = {
            StateChannels.State.Start: {
                Type<CommitSeed>(): StateChannels.StateTransition(
                    handler: CommitSeedHandler(),
                    newSignerRoles: ["!initiator"],
                    newStates: [StateChannels.State.NeedSeed]),
                Type<StateChannels.Resign>(): StateChannels.StateTransition(
                    handler: ResignationHandler(),
                    newSignerRoles: ["!signer"],
                    newStates: [StateChannels.State.Cleanup])
            },
            StateChannels.State.NeedSeed: {
                Type<ProvideSeed>(): StateChannels.StateTransition(
                    handler: ProvideSeedHandler(),
                    newSignerRoles: ["initiator"],
                    newStates: [StateChannels.State.MoveX]),
                Type<StateChannels.Resign>(): StateChannels.StateTransition(
                    handler: ResignationHandler(),
                    newSignerRoles: ["!signer"],
                    newStates: [StateChannels.State.Cleanup])
            },
            StateChannels.State.CoinFlip: {
                Type<RevealSeed>(): StateChannels.StateTransition(
                    handler: RevealSeedHandler(),
                    newSignerRoles: ["player"],
                    newStates: [StateChannels.State.MoveX]),
                Type<StateChannels.Resign>(): StateChannels.StateTransition(
                    handler: ResignationHandler(),
                    newSignerRoles: ["!signer"],
                    newStates: [StateChannels.State.Cleanup])
            },
            StateChannels.State.MoveX: {
                Type<RevealSeed>(): StateChannels.StateTransition(
                    handler: MoveHandler(),
                    newSignerRoles: ["player", "!signer"],
                    newStates: [StateChannels.State.MoveO]),
                Type<StateChannels.Resign>(): StateChannels.StateTransition(
                    handler: ResignationHandler(),
                    newSignerRoles: ["!signer"],
                    newStates: [StateChannels.State.Cleanup])
            },
            StateChannels.State.MoveO: {
                Type<RevealSeed>(): StateChannels.StateTransition(
                    handler: MoveHandler(),
                    newSignerRoles: ["player", "!signer"],
                    newStates: [StateChannels.State.MoveX]),
                Type<StateChannels.Resign>(): StateChannels.StateTransition(
                    handler: ResignationHandler(),
                    newSignerRoles: ["!signer"],
                    newStates: [StateChannels.State.Cleanup])
            }
        }
    }

    access(all) struct ResignationHandler : StateChannels.ActionHandler {
        access(all) fun handleAction(context: StateChannels.ChannelContext, action: {StateChannels.Action}) : StateChannels.ChannelContext {
            let otherParticipantList = context.participants.values.filter(
                view fun (_ p: StateChannels.Participant):Bool {
                    return !p.hasRole("signer")
                }
            ) 

            return context.removeSigner().updateSigner(id:otherParticipantList[0].id).updateState(StateChannels.State.Cleanup)
        }
    }

    access(all) struct CloseChannel: StateChannels.Action {
    }

    access(all) struct CloseHandler: StateChannels.ActionHandler {
        access(all) fun handleAction(context: StateChannels.ChannelContext, action: {StateChannels.Action}) : StateChannels.ChannelContext {
            pre {
                context.participants.length == 1: "Can only close the channel when one participant is left"
            }

            return context.removeSigner()
        }
    }

    access(all) struct CommitSeed : StateChannels.Action {
        access(all) let commitment: UInt256

        init(commitment: UInt256) {
            self.commitment = commitment
        }
    }

    access(all) struct CommitSeedHandler : StateChannels.ActionHandler {
        access(all) fun handleAction(context: StateChannels.ChannelContext, action: {StateChannels.Action}) : StateChannels.ChannelContext {
            var appContext: TicTacPeer.TicTacToeContext = context.appContext as! TicTacToeContext
            let commitAction: TicTacPeer.CommitSeed = action as! CommitSeed

            appContext = appContext.addP1SeedCommitment(p1SeedCommitment: commitAction.commitment)

            return context.updateState(StateChannels.State.NeedSeed).updateSigner(id:1).updateAppContext(appContext)
        }
    }

    access(all) struct ProvideSeed : StateChannels.Action {
        access(all) let contribution: UInt256

        init(contribution: UInt256) {
            self.contribution = contribution
        }
    }

    access(all) struct ProvideSeedHandler : StateChannels.ActionHandler {
        access(all) fun handleAction(context: StateChannels.ChannelContext, action: {StateChannels.Action}) : StateChannels.ChannelContext {
            var appContext: TicTacPeer.TicTacToeContext = context.appContext as! TicTacToeContext
            let provideAction: TicTacPeer.ProvideSeed = action as! ProvideSeed

            appContext = appContext.addP2SeedContribution(p2SeedContribution: provideAction.contribution)

            return context.updateState(StateChannels.State.CoinFlip).updateSigner(id:0).updateAppContext(appContext)
        }
    }

    access(all) struct RevealSeed: StateChannels.Action {
        access(all) let seed: UInt256
        access(all) let salt: UInt256

        init(seed: UInt256, salt: UInt256) {
            self.seed = seed
            self.salt = salt
        }
    }

    access(all) struct RevealSeedHandler: StateChannels.ActionHandler {
        access(all) fun handleAction(context: StateChannels.ChannelContext, action: {StateChannels.Action}) : StateChannels.ChannelContext {
            var appContext = context.appContext as! TicTacToeContext
            let revealAction = action as! RevealSeed

            var hashedData = revealAction.seed.toBigEndianBytes()
            hashedData.concat(revealAction.salt.toBigEndianBytes())

            let correctCommitment = UInt256.fromBigEndianBytes(HashAlgorithm.SHA3_256.hash(hashedData))!

            assert(appContext.p1SeedCommitment == correctCommitment, message: "Revealed seed doesn't match commitment")

            let channelSeed = revealAction.seed ^ appContext.p2SeedContribution

            let startingPlayer = UInt32(channelSeed % 2)

            let playerList = context.participants.values.filter(
                view fun (_ p: StateChannels.Participant):Bool {
                    return p.hasRole("player")
                }
            )

            let startingPlayerId = playerList[startingPlayer].id

            return context.updateState(StateChannels.State.MoveX).updateSigner(id:startingPlayerId)
        }
    }

    access(all) struct Move: StateChannels.Action {
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

    access(all) struct MoveHandler: StateChannels.ActionHandler {
        access(all) fun handleAction(context: StateChannels.ChannelContext, action: {StateChannels.Action}) : StateChannels.ChannelContext {
            var appContext = context.appContext as! TicTacToeContext
            let moveAction = action as! Move

            assert(appContext.boardContents(cellX: moveAction.x, cellY: moveAction.y) == 0, message: "Attempt to play in an occupied cell")

            let playerSymbol: UInt8 = (context.state == StateChannels.State.MoveX) ? 1 : 2
            appContext = appContext.modifyBoard(cellX: moveAction.x, cellY: moveAction.y, newValue: playerSymbol)

            let otherPlayerList = context.participants.values.filter(
                view fun (_ p: StateChannels.Participant):Bool {
                    return p.hasRole("player") && !p.hasRole("signer")
                }
            )

            return context.updateAppContext(appContext).updateSigner(id:otherPlayerList[0].id)
        }
    }
}