-- Originally MoveableContainer from BalaLib by Toeler (https://github.com/Toeler/Balatro-HandPreview/blob/main/Mods/BalaLib/BalaLib.lua) used under GPLv3
-- Modified for use in Ankh by MathIsFun0 (https://github.com/MathIsFun0/Ankh)
-- Further modified for use in SystemClock by Breezebuilder
-- Further modified for use in QuickHand Selector
--
-- Because of the above lineage this file, and therefore this mod, is GPLv3.

local DraggableContainer = UIBox:extend()

function DraggableContainer:init(args)
	Moveable.init(self, args)

	self.states.drag.can = args.can_drag or false
	self.states.collide.can = true
	-- Balatro only turns a press into a click when the cursor moved less than
	-- G.MIN_CLICK_DIST, so click and drag can both live on the same node.
	self.states.click.can = true
	-- Required: UIBox:draw iterates this (engine/ui.lua:295). We call Moveable.init
	-- rather than UIBox.init, so UIBox's own initialisation of it never runs.
	self.draw_layers = {}

	self.definition = args.definition

	if args.config then
		self.config = args.config
		if self.config.h_popup then
			self.config.h_popup_config = self.config.h_popup_config or { align = self.T.y > G.ROOM.T.h / 2 and 'tm' or 'bm' }
			self.config.h_popup_config.parent = self
		end
		args.config.major = args.config.major or args.config.parent or self

		self:set_alignment({
			major = args.config.major,
			type = args.config.align or args.config.type or '',
			bond = args.config.bond or 'Strong',
			offset = args.config.offset or { x = 0, y = 0 },
		})
		self:set_role({
			xy_bond = args.config.xy_bond,
			r_bond = args.config.r_bond,
			wh_bond = args.config.wh_bond or 'Weak',
			scale_bond = args.config.scale_bond or 'Weak',
		})
	end

	self:set_parent_child(self.definition, nil)
	self.Mid = self.Mid or self.UIRoot
	self:calculate_xywh(self.UIRoot, self.T)

	self.T.w = self.UIRoot.T.w
	self.T.h = self.UIRoot.T.h
	self.UIRoot:set_wh()

	self.UIRoot:set_alignments()

	self.VT.x = args.VT.x or self.T.x
	self.VT.y = args.VT.y or self.T.y
	self.VT.w, self.VT.h = self.T.w, self.T.h

	self.UIRoot:initialize_VT(true)

	self.zoom = args.zoom or args.config.zoom
	if self.zoom then self.UIRoot:set_zoom(true, true) end

	-- Looks unused but is not: game.lua splits G.I.UIBOX into two draw passes on this
	-- field. Without it the widget draws underneath the cards.
	self.attention_text = 'DraggableContainer'

	table.insert(G.I.UIBOX, self)
end

-- SystemClock installs the same helpers on Moveable. Guard so whichever mod loads
-- first wins and we never end up with two conflicting definitions.
if not Moveable.set_zoom then
	function Moveable:set_zoom(state, recursive, force)
		if self.zoom == state and not force then return end

		self.zoom = state
		if self.config.object then self.config.object.zoom = state end

		if recursive and self.children then
			for _, v in pairs(self.children) do
				v:set_zoom(state, true, force)
			end
		end
	end
end

if not Moveable.set_hover_state then
	function Moveable:set_hover_state(state, recursive, force)
		if self.states.hover.is == state and not force then return end

		self.states.hover.is = state
		if self.config.object then self.config.object.states.hover.is = state end

		if recursive and self.children then
			for _, v in pairs(self.children) do
				v:set_hover_state(state, true, force)
			end
		end
	end
end

if not Moveable.set_drag_state then
	function Moveable:set_drag_state(state, recursive, force)
		if self.states.drag.is == state and not force then return end

		self.states.drag.is = state
		if self.config.object then self.config.object.states.drag.is = state end

		if recursive and self.children then
			for _, v in pairs(self.children) do
				v:set_drag_state(state, true, force)
			end
		end
	end
end

function DraggableContainer:hover()
	if self.states.drag.can then
		self:juice_up(0.05, 0.02)
		play_sound('chips1', math.random() * 0.1 + 0.55, 0.15)
		if self.zoom then
			self.UIRoot:set_hover_state(true, true)
		end
	end

	UIBox.hover(self)
end

function DraggableContainer:stop_hover()
	if self.zoom then
		self.UIRoot:set_hover_state(false, true)
	end
	UIBox.stop_hover(self)
end

function DraggableContainer:drag()
	if self.zoom then
		self.UIRoot:set_drag_state(true, true)
	end
	UIBox.drag(self)
end

function DraggableContainer:stop_drag()
	if self.zoom then
		self.UIRoot:set_drag_state(false, true)
	end

	if self.config.h_popup then
		self.config.h_popup_config.align = self.T.y > G.ROOM.T.h / 2 and 'tm' or 'bm'
	end

	UIBox.stop_drag(self)
end

return DraggableContainer
