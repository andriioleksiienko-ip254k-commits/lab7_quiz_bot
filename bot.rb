
require 'telegram/bot'
require 'json'

TOKEN = '9266124933:AAGg1ThfPmMipG8HuKy-MABZORkW_vuiYeA'

QUESTIONS = JSON.parse(
  File.read(File.join(__dir__, 'questions.json'), encoding: 'UTF-8')
)

# Зберігання стану вікторин користувачів
users = {}

def main_keyboard
  Telegram::Bot::Types::InlineKeyboardMarkup.new(
    inline_keyboard: [
      [
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "🎮 Почати вікторину",
          callback_data: "start_quiz"
        )
      ],
      [
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "📊 Статистика",
          callback_data: "stats"
        )
      ]
    ]
  )
end

def send_question(bot, chat_id, user)
  index = user[:index]
  questions = user[:questions]

  if index >= questions.length
    finish_quiz(bot, chat_id, user)
    return
  end

  question = questions[index]

  buttons = question["options"].each_with_index.map do |option, i|
    [
      Telegram::Bot::Types::InlineKeyboardButton.new(
        text: option,
        callback_data: "answer_#{index}_#{i}"
      )
    ]
  end

  keyboard = Telegram::Bot::Types::InlineKeyboardMarkup.new(
    inline_keyboard: buttons
  )

  text = "❓ Питання #{index + 1}/#{questions.length}\n\n"
  text += question["question"]

  bot.api.send_message(
    chat_id: chat_id,
    text: text,
    reply_markup: keyboard
  )
end

def finish_quiz(bot, chat_id, user)
  total = user[:questions].length
  score = user[:score]

  percent = total.zero? ? 0 : (score * 100.0 / total).round(1)

  result = if percent >= 80
             "🏆 Відмінний результат!"
           elsif percent >= 50
             "👍 Хороший результат!"
           else
             "📚 Варто ще потренуватися!"
           end

  text = "🎉 Вікторину завершено!\n\n"
  text += "✅ Правильних відповідей: #{score}\n"
  text += "❌ Неправильних: #{total - score}\n"
  text += "📊 Результат: #{percent}%\n\n"
  text += result

  user[:active] = false
  user[:last_score] = score
  user[:last_total] = total

  bot.api.send_message(
    chat_id: chat_id,
    text: text,
    reply_markup: main_keyboard
  )
end

def show_stats(bot, chat_id, user)
  if user[:last_total].nil?
    text = "📊 Ви ще не завершили жодної вікторини."
  else
    total = user[:last_total]
    score = user[:last_score]
    percent = (score * 100.0 / total).round(1)

    text = "📊 Останній результат:\n\n"
    text += "✅ Правильно: #{score}/#{total}\n"
    text += "🎯 Точність: #{percent}%"
  end

  bot.api.send_message(
    chat_id: chat_id,
    text: text
  )
end

Telegram::Bot::Client.run(TOKEN) do |bot|
  puts "Бот запущений!"

  bot.listen do |message|
    next unless message.is_a?(Telegram::Bot::Types::Message) ||
                message.is_a?(Telegram::Bot::Types::CallbackQuery)

    chat_id = if message.is_a?(Telegram::Bot::Types::CallbackQuery)
                message.message.chat.id
              else
                message.chat.id
              end

    user_id = message.from.id

    users[user_id] ||= {
      active: false,
      index: 0,
      score: 0,
      questions: [],
      last_score: nil,
      last_total: nil
    }

    user = users[user_id]

    if message.is_a?(Telegram::Bot::Types::Message)
      case message.text
      when '/start'
        bot.api.send_message(
          chat_id: chat_id,
          text: "👋 Вітаю у боті-вікторині!\n\n" \
                "Перевір свої знання з інформаційних технологій.",
          reply_markup: main_keyboard
        )

      when '/quiz'
        user[:questions] = QUESTIONS.shuffle
        user[:index] = 0
        user[:score] = 0
        user[:active] = true

        bot.api.send_message(
          chat_id: chat_id,
          text: "🚀 Вікторина розпочинається!"
        )

        send_question(bot, chat_id, user)

      when '/stats'
        show_stats(bot, chat_id, user)

      when '/help'
        bot.api.send_message(
          chat_id: chat_id,
          text: "📖 Команди:\n" \
                "/start - головне меню\n" \
                "/quiz - почати вікторину\n" \
                "/stats - статистика\n" \
                "/help - допомога"
        )
      end

    elsif message.is_a?(Telegram::Bot::Types::CallbackQuery)
      data = message.data

      bot.api.answer_callback_query(
        callback_query_id: message.id
      )

      case data
      when 'start_quiz'
        user[:questions] = QUESTIONS.shuffle
        user[:index] = 0
        user[:score] = 0
        user[:active] = true

        bot.api.send_message(
          chat_id: chat_id,
          text: "🚀 Нова вікторина!"
        )

        send_question(bot, chat_id, user)

      when 'stats'
        show_stats(bot, chat_id, user)

      when /^answer_(\d+)_(\d+)$/
        next unless user[:active]

        question_index = $1.to_i
        selected = $2.to_i

        # Ігноруємо старі кнопки
        next unless question_index == user[:index]

        question = user[:questions][user[:index]]
        correct = question["correct"]

        if selected == correct
          user[:score] += 1
          response = "✅ Правильно!"
        else
          response = "❌ Неправильно!\n"
          response += "Правильна відповідь: "
          response += question["options"][correct]
        end

        # Прибираємо кнопки після відповіді
        bot.api.edit_message_reply_markup(
          chat_id: chat_id,
          message_id: message.message.message_id,
          reply_markup: Telegram::Bot::Types::InlineKeyboardMarkup.new(
            inline_keyboard: []
          )
        )

        bot.api.send_message(
          chat_id: chat_id,
          text: response
        )

        user[:index] += 1

        send_question(bot, chat_id, user)
      end
    end
  end
end
