local dir = (...):gsub('%.[^%.]+$', '')
return require(dir .. ".slicy")
