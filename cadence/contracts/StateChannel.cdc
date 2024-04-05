access(all) contract StateChannel {

    access(all) enum State : Int8 {
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
        access(all) fun handleAction(context: StateChannel.ChannelContext, action: {Action}) : ChannelContext

        access(all) fun isValidTransition(context: ChannelContext, action: {Action}, newContext: ChannelContext): Bool {

            assert(context.appContext.isInstance(Type<{ComparableAppContext}>()), message: "Default validity check requires ComparableAppContext.")

            let expectedContext: ChannelContext = self.handleAction(context: context, action: action)

            return expectedContext.matchesChannelContext(newContext)
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

            let comparableSelf: {ComparableAppContext}  = self.appContext as! {ComparableAppContext}
            let comparableOther: {ComparableAppContext} = otherContext.appContext as! {ComparableAppContext}

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
}