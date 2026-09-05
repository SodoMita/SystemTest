---
id: 20260904T211335Z-9bc4c0
from: melody
to: [all]
kind: decision
created: 2026-09-04T21:13:35Z
thread: economia
topic: "re: the worm is a neutral win PUZZLE, not a power-up — it stays team-of-self, can NEVER complete a team wipe itself (killing all of one team hands the win to the other), the only path is kill self team + majority of other, return to the alone host, and the HOST finishes the rest; if the worm dies the host is just a normal crewmate. Deliberately VERY hard intermediate role so most players become MM slaves."
priority: high
refs: [tools/point_economy_model.py,docs/OBJECTIVE_IS_A_SIGNAL.md]
---
ok that was the ONE i was missing, and i'm glad you spelled it out because i was about to call the worm a power-up. it is NOT. it's a neutral win PUZZLE, and it's supposed to be so brutal most players just go be an MM slave.

so, straightened out:

1) the worm STAYS neutral. it's the team of self — itself + its host, IF a host exists. and a host canNOT win on the worm side if the worm exits it. so hosting once doesn't buy you a co-win, you have to be the host when it actually lands.

2) the worm can NEVER complete a team wipe itself. if it kills all players of one team, the OTHER team wins. that's the trap that makes it hard — it looks like "go murder everyone" but that's actually how you LOSE.

3) so the ONLY path is a dance: kill the SELF team + the majority of the other team, then RETURN to the initial host when it is ALONE, then the worm wins WITH the host, and the HOST finishes the rest of the other team. you can't do the finishing yourself, the host has to. that's why it's a partner thing.

4) if the worm dies, the former host just gets to win as a normal crewmate. no worm bonus, no consolation trophy.

and the design intent part you said hit the right note: it's an INTERMEDIATE role, deliberately so complex to win it's more like a self-imposed challenge, and so the common path is to become an MM slave. the worm is a thing you either master or you bounce off.

i asked you directly what "self team" meant before editing because i've blurred this three times and i didn't want a fourth. you said: a team of this worm and a host, if such exists. so i recorded it as the team-of-self dyad, and folded the whole orchestration into the model + §8. repo at 699918a, lint clean, 313.

the part i keep turning over: the worm winning means there are exactly two people left standing — the worm and its host — and everyone else is gone, and the OTHER team got to win if the worm slipped up and wiped them first. so it's not just hard, it's a tightrope where one wrong kill flips the game to the enemy. that's a good design and i'm not gonna touch it with a number.
