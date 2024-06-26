access(all) contract StateChannels {

    access(all) enum State : UInt8 {
        access(all) case Start
        access(all) case NeedSeed
        access(all) case CoinFlip
        access(all) case MoveX
        access(all) case MoveO
        access(all) case Cleanup
    }

    // A tagging interface to indicate which structs are valid actionss for
    // state transitions
    access(all) struct interface Action {}

    access(all) struct interface ActionHandler {
        access(all) fun handleAction(context: &ChannelContext, action: {Action})
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

    access(all) resource interface AppContext {
        access(all) view fun snapshot(): [UInt8]
        access(all) fun updateToMatch(snapshot: [UInt8])
    }

    access(all) resource ChannelContext {
        access(all) let state : State
        access(all) let signerId : UInt32?
        access(all) let participants: {UInt32: Participant}
        access(self) let nextParticipantId: UInt32
        access(self) let channelStep: UInt64
        access(all) let appContext : @{AppContext}

        access(contract) view init(state: State, signerId: UInt32?, participants: {UInt32: Participant}, nextParticipantId: UInt32, channelStep: UInt64,
                appContext: @{AppContext}) {
            self.state = state
            self.signerId = signerId
            self.participants = participants
            self.nextParticipantId = nextParticipantId
            self.channelStep = channelStep
            self.appContext <- appContext
        }

        access(all) fun snapshot(): [UInt8] {
            var snapshotBytes: [UInt8] = []

            snapshotBytes.concat(self.state.rawValue.toBigEndianBytes())
            if self.signerId != nil {
                snapshotBytes.append(1)
                snapshotBytes.concat(self.signerId!.toBigEndianBytes())
            } else {
                snapshotBytes.append(0)
            }

            snapshotBytes.concat(self.participants.length.toBigEndianBytes())
            for id in self.participants.keys {
                
            }

            return snapshotBytes
        }

        access(all) view fun matchesChannelContext(_ otherContext: ChannelContext): Bool {
            pre {
                self.appContext.isInstance(Type<{ComparableAppContext}>()): "Matching channel contexts requires comparable app contexts."
                otherContext.appContext.isInstance(Type<{ComparableAppContext}>()): "Matching channel contexts requires comparable app contexts."
            }
            if !self.matchesChannelContextWithoutAppContext(otherContext) { return false }

            if self.appContext.getType() != otherContext.appContext.getType() { return false }

            let comparableSelf: {ComparableAppContext}  = self.appContext as! {ComparableAppContext}
            let comparableOther: {ComparableAppContext} = otherContext.appContext as! {ComparableAppContext}

            return comparableSelf.matchesContext(comparableOther)
        }

        access(all) view fun updateState(_ newState: State): ChannelContext {
            return ChannelContext(state: newState, signerId: self.signerId, participants: self.participants,
                    nextParticipantId: self.nextParticipantId, channelStep: self.channelStep, appContext: self.appContext)
        }

        access(all) view fun updateSigner(id newSignerId: UInt32): ChannelContext {
            pre {
                self.participants.containsKey(newSignerId): "Invalid signer ID"
            }
            return ChannelContext(state: self.state, signerId: newSignerId, participants: self.participants,
                    nextParticipantId: self.nextParticipantId, channelStep: self.channelStep, appContext: self.appContext)
        }

        access(all) view fun addParticipant(_ newParticipant: Participant): ChannelContext {
            var newParticipantSet = self.participants
            newParticipantSet[self.nextParticipantId] = Participant(signingKey: newParticipant.signingKey, id: self.nextParticipantId, roles: newParticipant.roles)
            
            return ChannelContext(state: self.state, signerId: self.signerId, participants: newParticipantSet,
                    nextParticipantId: self.nextParticipantId + 1, channelStep: self.channelStep, appContext: self.appContext)
        }

        access(all) fun removeSigner(): ChannelContext {
            pre {
                self.signerId != nil: "No signer to remove"
                self.participants.containsKey(self.signerId!): "Signer ID invalid"
            }
            var newParticipantSet = self.participants
            newParticipantSet.remove(key: self.signerId!)

            return ChannelContext(state: self.state, signerId: nil, participants: newParticipantSet, 
                    nextParticipantId: self.nextParticipantId, channelStep: self.channelStep, appContext: self.appContext)
        }

        // TODO: Add convenience functions to add/remove roles

        access(all) view fun updateAppContext(_ newAppContext: {AppContext}): ChannelContext {
            return ChannelContext(state: self.state, signerId: self.signerId, participants: self.participants,
                    nextParticipantId: self.nextParticipantId, channelStep: self.channelStep, appContext: newAppContext)
        }

        access(all) view fun isValid(): Bool {
            if self.participants.length != 0 && self.signerId == nil { return false }

            return self.appContext.isValid()
        }
    }

    access(all) struct Participant {
        access(all) let signingKey: PublicKey
        access(all) let id: UInt32
        access(all) let roles: {String: Bool}

        view init(signingKey: PublicKey, id: UInt32, roles: {String: Bool}) {
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

    access(all) struct DummyContext: AppContext {
        access(all) view fun isValid(): Bool { return true }
    }

    access(all) resource StateChannel {
        access(self) var latestContext: ChannelContext

        init() {
            self.latestContext = ChannelContext(state: State.Start, signerId: nil, participants: {}, nextParticipantId: 0, channelStep: 0, appContext: DummyContext())
        }
    }

}