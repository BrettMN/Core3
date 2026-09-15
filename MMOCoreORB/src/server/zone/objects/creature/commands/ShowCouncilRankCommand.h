/*
				Copyright <SWGEmu>
		See file COPYING for copying conditions.*/

#ifndef SHOWCOUNCILRANKCOMMAND_H_
#define SHOWCOUNCILRANKCOMMAND_H_

#include "server/zone/objects/player/sui/listbox/SuiListBox.h"
#include "server/zone/objects/player/sui/callbacks/EnclaveCouncilRankSuiCallback.h"

class ShowCouncilRankCommand : public QueueCommand {
public:

	ShowCouncilRankCommand(const String& name, ZoneProcessServer* server)
		: QueueCommand(name, server) {

	}

	int doQueueCommand(CreatureObject* creature, const uint64& target, const UnicodeString& arguments) const {

		if (!checkStateMask(creature))
			return INVALIDSTATE;

		if (!checkInvalidLocomotions(creature))
			return INVALIDLOCOMOTION;

		PlayerObject* ghost = creature->getPlayerObject();

		if (ghost == nullptr)
			return GENERALERROR;

		// NON-STOCK: a member of both councils picks one with "light" or "dark";
		// otherwise the council the character belongs to is shown, as stock.
		String args = arguments.toString().toLowerCase();
		int playerCouncil = 0;

		if (args.contains("dark") && ghost->getFrsRankForCouncil(FrsManager::COUNCIL_DARK) >= 0)
			playerCouncil = FrsManager::COUNCIL_DARK;
		else if (args.contains("light") && ghost->getFrsRankForCouncil(FrsManager::COUNCIL_LIGHT) >= 0)
			playerCouncil = FrsManager::COUNCIL_LIGHT;
		else if (ghost->getFrsRankForCouncil(FrsManager::COUNCIL_LIGHT) >= 0)
			playerCouncil = FrsManager::COUNCIL_LIGHT;
		else if (ghost->getFrsRankForCouncil(FrsManager::COUNCIL_DARK) >= 0)
			playerCouncil = FrsManager::COUNCIL_DARK;

		if (playerCouncil == 0)
			return GENERALERROR;

		ManagedReference<SuiListBox*> box = new SuiListBox(creature, SuiWindowType::ENCLAVE_VOTING, SuiListBox::HANDLETWOBUTTON);
		box->setCallback(new EnclaveCouncilRankSuiCallback(server->getZoneServer(), playerCouncil));
		box->setPromptText("Select the rank whose members you wish to view.");
		box->setPromptTitle("@force_rank:rank_selection"); // Rank Selection
		box->setUsingObject(creature);
		box->setOkButton(true, "@ok");
		box->setCancelButton(true, "@cancel");

		for (int i = 1; i < 12; i++) {
			String stfRank = "@force_rank:rank" + String::valueOf(i);
			String rankString = StringIdManager::instance()->getStringId(stfRank.hashCode()).toString();
			box->addMenuItem(rankString);
		}

		ghost->addSuiBox(box);
		creature->sendMessage(box->generateMessage());

		return SUCCESS;
	}

};

#endif //SHOWCOUNCILRANKCOMMAND_H_
