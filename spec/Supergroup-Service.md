SUPERGROUP (10k) 9 dec 2024
---------------------------

Proposal sketch for service to update the trust (untrust) list of supergroup

Steps executed every (randomized) 30 minutes
--------------------------------------------
[current_iteration =+ 1]

[1] Nethermind RPC ─────► Get complete list of all v2 humans 
                       registered in Hub -> list A

[2] Cache/db ─────────► For each human p, check if they are blacklisted:
    (Human:                   
     - blacklisted           a) if blacklisted -> remove from list A
     - last_included_iter    b) if `last_included_iter = current_iteration-1`
                                -> add to list B (and/or B is kept in working memory)
                                ( list B = current list of group's trust connections)
    

[3] LBP index ────────► For all humans in list B & list A: ((priority for existing trusted humans)
    "has human CRC         - if "backed LBP" -> add to list C
    been (sufficiently)                         and remove from A and from B
    backed?"                
                        For all humans in list A      
                           - if "backed LBP" -> add to list C
                                                and remove from A and from B
                       -> COUNT |C| < 10k (else skip to step 5)

[4] Now find all "unbacked friends" to trust     
    
    For remaining in list A (list B):
    [4a] Nethermind ────► For each a in A: get `trusted_by` list from RPC
         RPC           and intersect with list C
                       If not ≥ 3 or more of their trust connections are backing their CRC
                       remove a from A

    [4b]              For each b in B: if b in A:  -- (sort or rand B?)
                      (i.e. b was trusted before)
                     -> add b to C (remove from B & A)
                       sort b's backers by ascending `n_friends_backed`
                       and mark top 3 backers +1 on `n_friends_backed`

    [4c]             For each `a` remaining in A:   -- (sort or rand A?)
                     sort `a`'s backers by ascending `n_friends_backed`
                     -> if top 3 backers each have backed < 2 friends
                        ->  add `a` to C (and remove from A)
                            and +1 on top 3 trackers

            repeat [4b] and [4c] while |C| < 10k total

[5]                  list C is now "accounts we want to trust"
                     and compare with "current trust list"
                     -> Δ_JOINERS and Δ_LEAVERS
                     
                     if |Δ_JOINERS| - |Δ_LEAVERS| > Threshold
                     (alternatively: if |Δ_JOINERS| > Threshold)
                     -> truncate Δ_JOINERS
                        how? by first (randomly) selecting backed accounts
                             then further (randomly) selecting unbacked friends
                     -> apply to group & update cache/db