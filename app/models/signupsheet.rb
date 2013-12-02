class Signupsheet < ActiveRecord::Base

  include ManageTeamHelper




  def self.signup_team ( assignment_id, user_id, topic_id )
    users_team = SignedUpUser.find_team_users(assignment_id.id, user_id)
    puts ("Assignment is " + assignment_id.id.to_s + " team is " + users_team.to_s + " user is " + user_id.to_s + " topic is " + topic_id.to_s)
    if users_team.size == 0
      #if team is not yet created, create new team.
      team = AssignmentTeam.create_team_and_node(assignment_id)
      puts (team.id.to_s + "is team id " + team.parent_id.to_s + "is parent id")
      user = User.find(user_id)
      teamuser = ManageTeamHelper.create_team_users(user, team.id)
     confirmationStatus = self.confirmtopic(team.id, topic_id, assignment_id, user_id)
    else
     confirmationStatus = self.confirmtopic(users_team[0].t_id, topic_id, assignment_id, user_id)
    end
  end

  def self.confirmtopic(creator_id, topic_id, assignment_id,user_id)
    #check whether user has signed up already
    user_signup = self.other_confirmed_topic_for_user(assignment_id, creator_id)

    #creator_id is team id
    sign_up = SignedUpUser.new
    sign_up.topic_id = topic_id
    sign_up.creator_id = creator_id

    result = false
    if user_signup.size == 0
      # Using a DB transaction to ensure atomic inserts
      ActiveRecord::Base.transaction do
        #check whether slots exist (params[:id] = topic_id) or has the user selected another topic
        if slotAvailable?(topic_id)
          sign_up.is_waitlisted = false

          #Update topic_id in participant table with the topic_id
          puts "Values of topic, assignment, and user id's "+ topic_id.to_s
          puts "Values of topic, assignment, and user id's "+ user_id.to_s
          puts "Values of topic, assignment, and user id's "+ assignment_id.to_s

          participant = Participant.find_by_user_id_and_parent_id(user_id, assignment_id)
              puts "PArticipants anme "+ participant.name
          participant.update_topic_id(topic_id)
          puts "participant's topic id " + participant.topic_id.to_s
        else
          sign_up.is_waitlisted = true
        end
        if sign_up.save
          puts 'Saved'
          result = true
        end
      end
    else
      #If all the topics choosen by the user are waitlisted,
      for user_signup_topic in user_signup
        if user_signup_topic.is_waitlisted == false
          flash[:error] = "You have already signed up for a topic."
          return false
        end
      end

      # Using a DB transaction to ensure atomic inserts
      ActiveRecord::Base.transaction do
        #check whether user is clicking on a topic which is not going to place him in the waitlist
        if !slotAvailable?(topic_id)
          sign_up.is_waitlisted = true
          if sign_up.save
            result = true
          end
        else
          #if slot exist, then confirm the topic for the user and delete all the waitlist for this user
          Waitlist.cancel_all_waitlists(creator_id, assignment_id)
          sign_up.is_waitlisted = false
          sign_up.save

          participant = Participant.find_by_user_id_and_parent_id(user_id, assignment_id)

          participant.update_topic_id(topic_id)
          participant = Participant.find_by_user_id_and_parent_id(user_id, assignment_id)
          result = true
        end
      end
    end

    result
  end

  def self.other_confirmed_topic_for_user(assignment_id, creator_id)

    user_signup = SignedUpUser.find_user_signup_topics(assignment_id, creator_id)
    user_signup
  end

  # When using this method when creating fields, update race conditions by using db transactions
  def self.slotAvailable?(topic_id)
    SignUpTopic.slotAvailable?(topic_id)
  end

  def self.create_dependency_graph(topics,node)
    dg = RGL::DirectedAdjacencyGraph.new

    #create a graph of the assignment with appropriate dependency
    topics.collect { |topic|
      topic[1].each { |dependent_node|
        edge = Array.new
        #if a topic is not dependent on any other topic
        dependent_node = dependent_node.to_i
        if dependent_node == 0
          edge.push("fake")
        else
          #if we want the topic names to be displayed in the graph replace node to topic_name
          edge.push(SignUpTopic.find(dependent_node)[node])
        end
        edge.push(SignUpTopic.find(topic[0])[node])
        dg.add_edges(edge)
      }
    }
    #remove the fake vertex
    dg.remove_vertex("fake")
    dg
  end
end
